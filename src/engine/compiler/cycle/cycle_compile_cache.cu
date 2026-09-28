// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// cycle_compile_cache.cu: the cache, compiling and linking, the PTX header
#include "cycle_compile_internal.h"

// the target for relocatable cubin, then the target for LTO-IR
static CycleTarget s_cycle_lane_targets[2];

static const char s_cycle_cache_magic[] = "cycle image 2\n";

// the image a cache file holds for this very source; empty where there is none
std::vector<char> cycle_cache_read(const std::string &path, const std::string &source)
{
    std::vector<char> image;
    FILE *const file = fopen(path.c_str(), "rb");
    if (file == NULL)
    {
        return image;
    }
    std::vector<char> contents;
    char block[65536];
    size_t read = fread(block, 1u, sizeof(block), file);
    while (read != 0u)
    {
        contents.insert(contents.end(), block, block + read);
        read = fread(block, 1u, sizeof(block), file);
    }
    fclose(file);
    const size_t magic = sizeof(s_cycle_cache_magic) - 1u;
    const size_t head = magic + sizeof(unsigned long long);
    unsigned long long length = 0ull;
    if (contents.size() >= head)
    {
        memcpy(&length, &contents[magic], sizeof(length));
    }
    const int ok = (contents.size() >= head) && (memcmp(&contents[0], s_cycle_cache_magic, magic) == 0) &&
                   (length == source.size()) && ((contents.size() - head) > length) &&
                   (memcmp(&contents[head], source.data(), source.size()) == 0);
    if (ok)
    {
        // a source length the file read whole is below its size. It converts exactly
        image.assign(contents.begin() + (ptrdiff_t)(head + length), contents.end());
    }
    return image;
}

// the source and its image written beside the name and then renamed to it, and no reader finds half a file; a name
// already taken is left as it is
void cycle_cache_write(const std::string &folder, const std::string &path, const std::string &source,
                       const std::vector<char> &image)
{
#if defined(_WIN32)
    _mkdir(folder.c_str());
    const int process = _getpid();
#else
    mkdir(folder.c_str(), 0755);
    // a pid is positive. It converts exactly
    const int process = (int)getpid();
#endif
    char suffix[32];
    snprintf(suffix, sizeof(suffix), ".%d.partial", process);
    const std::string partial = path + suffix;
    FILE *const file = fopen(partial.c_str(), "wb");
    if (file == NULL)
    {
        return;
    }
    const unsigned long long length = source.size();
    const int written = (fwrite(s_cycle_cache_magic, 1u, sizeof(s_cycle_cache_magic) - 1u, file) ==
                         (sizeof(s_cycle_cache_magic) - 1u)) &&
                        (fwrite(&length, sizeof(length), 1u, file) == 1u) &&
                        (fwrite(source.data(), 1u, source.size(), file) == source.size()) &&
                        (fwrite(image.data(), 1u, image.size(), file) == image.size());
    const int closed = fclose(file) == 0;
    if (!written || !closed || (rename(partial.c_str(), path.c_str()) != 0))
    {
        remove(partial.c_str());
    }
}

// the source compiled by NVRTC as relocatable code for the device's architecture: a relocatable cubin, or LTO-IR where
// `lto`; empty where it refuses, its log then on stderr when reporting
std::vector<char> cycle_program_compile(const std::string &source, const char *name, int major, int minor, int lto,
                                        int report)
{
    CycleCompiler *const compiler = &g_cycle_compiler;
    std::vector<char> image;
    nvrtcProgram program = NULL;
    if (compiler->create(&program, source.c_str(), name, 0, NULL, NULL) != NVRTC_SUCCESS)
    {
        return image;
    }
    char architecture[48];
    snprintf(architecture, sizeof(architecture), "--gpu-architecture=sm_%d%d", major, minor);
    const char *const options[] = {architecture, "--std=c++17", "--relocatable-device-code=true", "-dlto"};
    const nvrtcResult compiled = compiler->compile(program, (lto != 0) ? 4 : 3, options);
    size_t size = 0u;
    const nvrtcResult sized = (lto != 0) ? compiler->ltoir_size(program, &size) : compiler->cubin_size(program, &size);
    if ((compiled == NVRTC_SUCCESS) && (sized == NVRTC_SUCCESS) && (size != 0u))
    {
        image.resize(size);
        const nvrtcResult taken =
            (lto != 0) ? compiler->ltoir(program, image.data()) : compiler->cubin(program, image.data());
        if (taken != NVRTC_SUCCESS)
        {
            image.clear();
        }
    }
    size_t log_size = 0u;
    if ((compiled != NVRTC_SUCCESS) && (report != 0) && (compiler->log_size(program, &log_size) == NVRTC_SUCCESS) &&
        (log_size > 1u))
    {
        std::vector<char> log(log_size);
        if (compiler->log(program, log.data()) == NVRTC_SUCCESS)
        {
            fprintf(stderr, "  cycle: NVRTC refused %s (%d):\n%s\n", name, (int)compiled, log.data());
        }
    }
    compiler->destroy(&program);
    return image;
}

// a program's relocatable image linked alone by nvJitLink into one cubin, its resident and its lane in the one text,
// with link-time optimization where `lto`; where `ptx` the program is PTX's text, NUL and all, which nvJitLink
// assembles as it links. Empty where it refuses, its log then on stderr when reporting
std::vector<char> cycle_program_link(const CycleTarget *lane_target, const std::vector<char> &object, int lto, int ptx,
                                     int report)
{
    CycleLinker *const linker = &g_cycle_linker;
    std::vector<char> cubin;
    char architecture[32];
    snprintf(architecture, sizeof(architecture), "-arch=sm_%d%d", lane_target->major, lane_target->minor);
    const char *options[] = {architecture, "-lto"};
    nvJitLinkHandle handle = NULL;
    if (linker->create(&handle, (lto != 0) ? 2u : 1u, options) != NVJITLINK_SUCCESS)
    {
        return cubin;
    }
    const nvJitLinkInputType kind = (lto != 0) ? NVJITLINK_INPUT_LTOIR : NVJITLINK_INPUT_CUBIN;
    const nvJitLinkInputType program_kind = (ptx != 0) ? NVJITLINK_INPUT_PTX : kind;
    size_t size = 0u;
    const int linked =
        (linker->add(handle, program_kind, object.data(), object.size(), "cycle_program") == NVJITLINK_SUCCESS) &&
        (linker->complete(handle) == NVJITLINK_SUCCESS) && (linker->cubin_size(handle, &size) == NVJITLINK_SUCCESS) &&
        (size != 0u);
    if (linked)
    {
        cubin.resize(size);
        if (linker->cubin(handle, cubin.data()) != NVJITLINK_SUCCESS)
        {
            cubin.clear();
        }
    }
    size_t log_size = 0u;
    if (!linked && (report != 0) && (linker->log_size(handle, &log_size) == NVJITLINK_SUCCESS) && (log_size > 1u))
    {
        std::vector<char> log(log_size);
        if (linker->log(handle, log.data()) == NVJITLINK_SUCCESS)
        {
            fprintf(stderr, "  cycle: nvJitLink refused a record program:\n%s\n", log.data());
        }
    }
    linker->destroy(&handle);
    return cubin;
}

// the target for the device and the kind of link, named once a process; it builds nothing and is always ready
const CycleTarget *cycle_target(int major, int minor, int lto, int report)
{
    CycleTarget *const lane_target = &s_cycle_lane_targets[(lto != 0) ? 1 : 0];
    if ((lane_target->tried != 0) && (lane_target->major == major) && (lane_target->minor == minor))
    {
        return lane_target;
    }
    lane_target->tried = 1;
    lane_target->ready = 1;
    lane_target->major = major;
    lane_target->minor = minor;
    lane_target->source = cycle_target_source(major, minor, lto);
    lane_target->hash = cycle_source_hash(lane_target->source);
    if (report != 0)
    {
        fprintf(stderr, "  cycle: lanes written for sm_%d%d as %s against %016llx, each with its own resident\n", major,
                minor, (lto != 0) ? "LTO-IR" : "relocatable cubin", lane_target->hash);
    }
    return lane_target;
}

// the .version, .target and .address_size lines of a PTX text, the first of each, in that order; empty where one is
// missing or the address size is not 64, which the lane's pointers are written for
static std::string cycle_ptx_header_lines(const char *ptx)
{
    std::string version;
    std::string target;
    std::string address_size;
    const char *line = ptx;
    while (*line != '\0')
    {
        const char *const end = strchr(line, '\n');
        // a line ends past its start, and its length is never negative
        const size_t length = (end != NULL) ? (size_t)(end - line) : strlen(line);
        const std::string text_line(line, length);
        if (version.empty() && (text_line.compare(0u, 9u, ".version ") == 0))
        {
            version = text_line;
        }
        else if (target.empty() && (text_line.compare(0u, 8u, ".target ") == 0))
        {
            target = text_line;
        }
        else if (address_size.empty() && (text_line.compare(0u, 14u, ".address_size ") == 0))
        {
            address_size = text_line;
        }
        line = (end != NULL) ? (end + 1) : (line + length);
    }
    const int complete = !version.empty() && !target.empty() && (address_size == ".address_size 64");
    return complete ? (version + "\n" + target + "\n" + address_size + "\n") : std::string();
}

static CyclePtxHeader s_cycle_ptx_header;

// the header's three lines; empty where NVRTC cannot be asked or does not answer, which leaves programs to the C source
const std::string &cycle_ptx_header(int major, int minor, int report)
{
    CyclePtxHeader *const header = &s_cycle_ptx_header;
    if ((header->tried != 0) && (header->major == major) && (header->minor == minor))
    {
        return header->lines;
    }
    header->tried = 1;
    header->major = major;
    header->minor = minor;
    header->lines.clear();
    CycleCompiler *const compiler = &g_cycle_compiler;
    if ((compiler->ptx_size == NULL) || (compiler->ptx == NULL))
    {
        return header->lines;
    }
    std::string question;
    cycle_format(question, "// PTX's header, asked for sm_%d%d of NVRTC %d.%d\n", major, minor, compiler->major,
                 compiler->minor);
    question += "extern \"C\" __global__ void cycle_probe(void)\n{\n}\n";
    const std::string folder = cycle_cache_folder();
    const std::string path = folder.empty() ? std::string() : cycle_cache_path(folder, question);
    const std::vector<char> kept = path.empty() ? std::vector<char>() : cycle_cache_read(path, question);
    std::string answer(kept.begin(), kept.end());
    const int found = !answer.empty();
    nvrtcProgram program = NULL;
    if (!found && (compiler->create(&program, question.c_str(), "cycle_probe.cu", 0, NULL, NULL) == NVRTC_SUCCESS))
    {
        char architecture[48];
        snprintf(architecture, sizeof(architecture), "--gpu-architecture=compute_%d%d", major, minor);
        const char *const options[] = {architecture};
        size_t size = 0u;
        if ((compiler->compile(program, 1, options) == NVRTC_SUCCESS) &&
            (compiler->ptx_size(program, &size) == NVRTC_SUCCESS) && (size > 1u))
        {
            std::vector<char> ptx(size);
            if (compiler->ptx(program, ptx.data()) == NVRTC_SUCCESS)
            {
                ptx[size - 1u] = '\0';
                answer = cycle_ptx_header_lines(ptx.data());
            }
        }
        compiler->destroy(&program);
        if (!answer.empty() && !path.empty())
        {
            cycle_cache_write(folder, path, question, std::vector<char>(answer.begin(), answer.end()));
        }
    }
    header->lines = answer;
    if (report != 0)
    {
        fprintf(stderr, "  cycle: PTX's header for sm_%d%d %s: %s\n", major, minor,
                found ? "read from the cache" : "asked of NVRTC", answer.empty() ? "none" : answer.c_str());
    }
    return header->lines;
}
