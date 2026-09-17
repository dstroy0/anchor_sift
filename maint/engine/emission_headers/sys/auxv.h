/* anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
 * SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
 *
 * Every use falls under AGPL-3.0-or-later unless you hold explicit permission, which is either a
 * negotiated commercial licensing contract or an educator's license issued to you personally.
 */
/**
 * @file auxv.h
 * @brief The two declarations an aarch64 arm's detection needs, for compiling it where no sysroot is.
 * @author dstroy0 (Douglas Quigg) <dquigg123@gmail.com>
 * @date 2026-09-16
 *
 * @note FOR GRADING EMITTED INSTRUCTIONS ONLY. NOTHING BUILT AGAINST THIS HEADER IS EVER LINKED OR
 *       RUN. maint/engine/verify_arm_asm.sh compiles an ARM arm to an object with clang and reads the
 *       instructions that came out. clang ships arm_neon.h and arm_sve.h and can target aarch64 from
 *       any host, but it ships no Linux C library, so a file including <sys/auxv.h> stops before the
 *       vector loops are ever compiled. This header supplies what that include provides and nothing
 *       more, so the loops reach the assembler.
 * @note What this cannot vouch for is detection. The two values below are the Linux ABI's, and a
 *       wrong one here would change which bit the arm tests without changing a single vector
 *       instruction. Emission grading never touched detection before this file existed, and it does
 *       not now. Only a run on the part checks detection.
 * @note Where a real aarch64 sysroot is present, the verifier uses the cross compiler and this header
 *       is not on the include path.
 */
#ifndef ANCHOR_EMISSION_SYS_AUXV_H
#define ANCHOR_EMISSION_SYS_AUXV_H

/** @brief The auxiliary vector entry holding hardware capability bits, as the Linux ABI numbers it. */
#define AT_HWCAP 16ul

/**
 * @brief Reads one entry of the auxiliary vector.
 *
 * @param[in] type The entry to read.
 * @return         Its value.
 * @note Declared and never defined. An object built against it is disassembled and never linked.
 */
unsigned long getauxval(unsigned long type);

#endif /* ANCHOR_EMISSION_SYS_AUXV_H */
