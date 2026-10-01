// SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
// pi_plane_png.cu: PNG pictures
#include "pi_plane_internal.h"

static void plane_crc(unsigned int *crc, const unsigned char *bytes, size_t count)
{
    for (size_t byte = 0u; byte < count; byte += 1u)
    {
        *crc ^= bytes[byte];
        for (unsigned int bit = 0u; bit < 8u; bit += 1u)
        {
            *crc = (*crc >> 1u) ^ (0xEDB88320u & (0u - (*crc & 1u)));
        }
    }
}

// big endian, as PNG writes every word
static void plane_put_word(std::vector<unsigned char> *out, unsigned int word)
{
    for (unsigned int byte = 0u; byte < 4u; byte += 1u)
    {
        // one byte of the word, taken from the bottom after the shift
        out->push_back((unsigned char)(word >> (24u - (8u * byte))));
    }
}

static void plane_chunk(std::vector<unsigned char> *out, const char *type, const std::vector<unsigned char> &data)
{
    // a chunk holds at most one picture, far below 2^31 bytes
    plane_put_word(out, (unsigned int)data.size());
    const size_t start = out->size();
    for (unsigned int letter = 0u; letter < 4u; letter += 1u)
    {
        // the chunk type is four ASCII letters
        out->push_back((unsigned char)type[letter]);
    }
    out->insert(out->end(), data.begin(), data.end());
    unsigned int crc = 0xFFFFFFFFu;
    plane_crc(&crc, out->data() + start, out->size() - start);
    plane_put_word(out, crc ^ 0xFFFFFFFFu);
}

// an 8-bit PNG, gray for one channel and color for three, its image data in stored deflate blocks. Nothing is
// encoded
int plane_png(const std::string &path, const std::vector<unsigned char> &pixels, unsigned long long width,
              unsigned long long height, unsigned int channels)
{
    const unsigned long long stride = width * channels;
    std::vector<unsigned char> raw;
    for (unsigned long long row = 0ull; row < height; row += 1ull)
    {
        raw.push_back(0u);
        raw.insert(raw.end(), pixels.begin() + (ptrdiff_t)(row * stride),
                   pixels.begin() + (ptrdiff_t)((row + 1ull) * stride));
    }
    std::vector<unsigned char> header;
    // the extents are below 2^16. They fit the header's words
    plane_put_word(&header, (unsigned int)width);
    plane_put_word(&header, (unsigned int)height);
    header.push_back(8u);
    header.push_back((channels == 3u) ? 2u : 0u);
    header.push_back(0u);
    header.push_back(0u);
    header.push_back(0u);
    std::vector<unsigned char> stream;
    stream.push_back(0x78u);
    stream.push_back(0x01u);
    size_t at = 0u;
    do
    {
        const size_t take = std::min((size_t)65535u, raw.size() - at);
        stream.push_back((at + take == raw.size()) ? 1u : 0u);
        // a stored block's length and its complement, little endian
        stream.push_back((unsigned char)(take & 0xFFu));
        stream.push_back((unsigned char)(take >> 8u));
        stream.push_back((unsigned char)(~take & 0xFFu));
        stream.push_back((unsigned char)((~take >> 8u) & 0xFFu));
        stream.insert(stream.end(), raw.begin() + (ptrdiff_t)at, raw.begin() + (ptrdiff_t)(at + take));
        at += take;
    } while (at < raw.size());
    unsigned int low = 1u;
    unsigned int high = 0u;
    for (size_t byte = 0u; byte < raw.size(); byte += 1u)
    {
        low = (low + raw[byte]) % 65521u;
        high = (high + low) % 65521u;
    }
    plane_put_word(&stream, (high << 16u) | low);
    std::vector<unsigned char> file = {137u, 80u, 78u, 71u, 13u, 10u, 26u, 10u};
    plane_chunk(&file, "IHDR", header);
    plane_chunk(&file, "IDAT", stream);
    plane_chunk(&file, "IEND", std::vector<unsigned char>());
    FILE *const out = fopen(path.c_str(), "wb");
    if (out == NULL)
    {
        return 0;
    }
    const size_t written = fwrite(file.data(), 1u, file.size(), out);
    const int closed = fclose(out) == 0;
    return closed && (written == file.size());
}

// the shape drawn with each bit a square of pixels, a one white, a zero black, and no bit gray
int plane_picture(const PlaneExtent &extent, const unsigned char *bits, const std::string &path)
{
    const unsigned long long longer = std::max(extent.height, extent.width);
    const unsigned long long scale = std::max(1ull, PLANE_PICTURE_MAX / longer);
    const unsigned long long width = extent.width * scale;
    const unsigned long long height = extent.height * scale;
    std::vector<unsigned char> pixels((size_t)(width * height));
    for (unsigned long long row = 0ull; row < height; row += 1ull)
    {
        for (unsigned long long column = 0ull; column < width; column += 1ull)
        {
            const long long cell = extent.cell[(size_t)(((row / scale) * extent.width) + (column / scale))];
            const unsigned char shade = (cell < 0ll) ? (unsigned char)PLANE_EMPTY_SHADE
                                                     : ((bits[cell] != 0u) ? (unsigned char)255u : (unsigned char)0u);
            pixels[(size_t)((row * width) + column)] = shade;
        }
    }
    return plane_png(path, pixels, width, height, 1u);
}

// the shape drawn sparse: each bit a dot with a gap around it, only the ones lit, the line's bits in red whatever
// their value, and the pixels no bit lands on a little lighter than the ground
int plane_sparse_picture(const PlaneExtent &extent, const unsigned char *bits, const PlaneLine &found,
                         const std::string &path)
{
    const unsigned long long cell = 7ull;
    const unsigned long long dot = 5ull;
    std::vector<unsigned char> marked(extent.cell.size(), 0u);
    // the extents are below 2^16. They fit a signed word
    const long long height = (long long)extent.height;
    const long long width = (long long)extent.width;
    for (long long index = 0ll; index < height * width; index += 1ll)
    {
        if (extent.cell[(size_t)index] != found.start)
        {
            continue;
        }
        for (unsigned long long walked = 0ull; walked < found.length; walked += 1ull)
        {
            // the walk is at most the line's length, below 2^15
            const long long row = (index / width) + ((long long)walked * found.step.row);
            const long long column = (index % width) + ((long long)walked * found.step.column);
            if ((row >= 0ll) && (row < height) && (column >= 0ll) && (column < width))
            {
                // the row and column are inside the shape. The index is never negative
                marked[(size_t)((row * width) + column)] = 1u;
            }
        }
    }
    const unsigned long long picture_width = extent.width * cell;
    const unsigned long long picture_height = extent.height * cell;
    std::vector<unsigned char> pixels((size_t)(picture_width * picture_height * 3ull), 0u);
    for (unsigned long long row = 0ull; row < picture_height; row += 1ull)
    {
        for (unsigned long long column = 0ull; column < picture_width; column += 1ull)
        {
            const size_t index = (size_t)(((row / cell) * extent.width) + (column / cell));
            const unsigned long long inside_row = row % cell;
            const unsigned long long inside_column = column % cell;
            const int in_dot =
                (inside_row >= 1ull) && (inside_row <= dot) && (inside_column >= 1ull) && (inside_column <= dot);
            unsigned char red = 0u;
            unsigned char green = 0u;
            unsigned char blue = 0u;
            if (extent.cell[index] < 0ll)
            {
                red = 24u;
                green = 24u;
                blue = 24u;
            }
            else if (in_dot && (marked[index] != 0u))
            {
                red = 255u;
                green = (bits[extent.cell[index]] != 0u) ? 96u : 0u;
                blue = green;
            }
            else if (in_dot && (bits[extent.cell[index]] != 0u))
            {
                red = 255u;
                green = 255u;
                blue = 255u;
            }
            const size_t at = (size_t)(((row * picture_width) + column) * 3ull);
            pixels[at] = red;
            pixels[at + 1u] = green;
            pixels[at + 2u] = blue;
        }
    }
    return plane_png(path, pixels, picture_width, picture_height, 3u);
}
