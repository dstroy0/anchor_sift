#!/usr/bin/env python3
# MMgr - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
# SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational
#
# Turn a recording into the binary sound representation the interdialect comparison runs on.
#
# Imported, not run. binary_sound.py is the driver.
#
# Four facts about hearing decide the shape of everything below.
#
# The waveform on its own is not enough. A vowel is a harmonic series under an envelope, and two
# recordings of one vowel share the envelope while the harmonics sit wherever the speaker's pitch
# put them. Comparing samples compares the harmonics. So the analysis is spectral, and the envelope
# comes off the source before anything is compared.
#
# What a person hears is not what the microphone recorded. Sensitivity is uneven across frequency
# and it differs between listeners by physiology and by how much hearing they have lost. The
# weighting is an argument here, an audiogram, and not a constant. NO_LOSS is the default.
#
# Some sounds are the same sound at different frequencies. A phone said by a small speaker and by a
# large one differs by a scaling of the whole spectrum. The bands below are log spaced, so that
# scaling is a shift along the band axis, and the magnitude of a Fourier transform along that axis
# is the same before and after the shift. That is what puts one phone at one code whoever says it.
#
# And some sounds that differ only in frequency mean different things. Stress is written with an
# acute in every orthography in this corpus, and a representation that threw pitch away to buy the
# invariance above would put a stressed form and an unstressed one at the same address. So the code
# has two fields. The segment field is shift invariant. The prosody field carries loudness, pitch
# against the speaker's own range, the movement of that pitch, and voicing, and it is what holds
# those two forms apart.

import math

import numpy

# The band centers the envelope is measured on. Log spaced, for the shift the third paragraph above
# describes. 80 Hz sits under the lowest fundamental a person speaks at, and 8000 Hz sits above the
# fricative energy that survives an mp3 encode.
LOW_HZ = 80.0
HIGH_HZ = 8000.0
BANDS = 64

# The window. 32 ms holds three periods of a 100 Hz voice, which is what the autocorrelation below
# needs to find the period, and it is short enough that a stop burst does not average away.
WINDOW_SECONDS = 0.032
HOP_SECONDS = 0.010

# How many frames are windowed at once. The frames are the large array here: twenty minutes at
# 44100 Hz is 135000 of them, 1411 samples each, and holding all of those windowed at once is over
# a gigabyte. What comes out per frame is 27 numbers, so only the frames are chunked.
CHUNK = 2048

# Where a person's fundamental lies. Under 60 Hz is the room and over 400 Hz is a child or a shout,
# and letting the search run past either end returns a harmonic in place of the fundamental.
LOW_PITCH_HZ = 60.0
HIGH_PITCH_HZ = 400.0

# How much of a frame's own energy the autocorrelation peak has to reach before the frame counts as
# voiced. Under this the peak is finding noise and the pitch read off it is meaningless.
VOICED_AT = 0.35

# How many terms the smoothed envelope keeps. Past this the detail being kept is the harmonic comb,
# which belongs to the source and is measured on its own by pitch().
ENVELOPE_TERMS = 20

# How wide each field of the code is. The segment field drops coefficient 0 of the transform,
# because that is the envelope's mean level, which is loudness and belongs to the other field.
SEGMENT_BITS = 24
PROSODY_BITS = 4

# Guards a logarithm against a silent frame.
TINY = 1e-12

# A listener with no measured loss. An audiogram is the frequencies a hearing test was run at and
# the loss in dB at each of them, which is how an audiologist reports one. The loss is taken off
# each band before loudness, so a band a listener cannot hear stops reaching the code at all.
NO_LOSS = ((250.0, 500.0, 1000.0, 2000.0, 4000.0, 8000.0), (0.0,) * 6)


def band_centers(low_hz=LOW_HZ, high_hz=HIGH_HZ, bands=BANDS):
    """The log spaced band centers the envelope is measured on, in Hz."""
    return numpy.exp(numpy.linspace(math.log(low_hz), math.log(high_hz), bands))


def band_gain(centers, audiogram=NO_LOSS):
    """The linear gain each band reaches one listener's ear at, from their audiogram.

    Interpolated across the frequencies the test was run at and held flat outside them, which is
    what numpy.interp does at both ends. A test reports six frequencies and there are 64 bands, so
    every band but a few is an interpolated value and the document says so.
    """
    measured_at, loss_db = audiogram
    at_band = numpy.interp(centers, numpy.asarray(measured_at, dtype=float),
                           numpy.asarray(loss_db, dtype=float))
    return numpy.power(10.0, -at_band / 20.0)


def band_matrix(width, rate, centers, gain):
    """The matrix turning one frame's power spectrum into the power each band is heard at.

    One column per band, holding the gain where an FFT bin falls inside that band and zero
    elsewhere. Squared, because the gain is an amplitude and this multiplies power. Built once per
    recording, because neither the window nor the rate changes inside one.

    The edges are the geometric means between neighboring centers, so a band near 8000 Hz is wide
    and one near 80 Hz is narrow. That is the shape of a person's own frequency resolution, and it
    is what the log spacing was chosen for.
    """
    at = numpy.fft.rfftfreq(width, 1.0 / rate)
    edges = numpy.concatenate(([centers[0] ** 2 / centers[1]],
                               numpy.sqrt(centers[:-1] * centers[1:]),
                               [centers[-1] ** 2 / centers[-2]]))
    held = numpy.zeros((len(at), len(centers)))
    for band in range(len(centers)):
        held[(at >= edges[band]) & (at < edges[band + 1]), band] = 1.0
    return held * (gain ** 2)


def frame_chunks(samples, rate, window_seconds=WINDOW_SECONDS, hop_seconds=HOP_SECONDS,
                 chunk=CHUNK):
    """The recording as Hann windowed frames, handed over a chunk of rows at a time."""
    width = int(round(window_seconds * rate))
    hop = int(round(hop_seconds * rate))
    if len(samples) < width:
        return
    count = 1 + ((len(samples) - width) // hop)
    shape = numpy.hanning(width)
    # A view and not a copy. Indexing it with one chunk's starts is what copies, so the whole
    # recording is never windowed at once.
    every = numpy.lib.stride_tricks.sliding_window_view(samples, width)
    for first in range(0, count, chunk):
        at = numpy.arange(first, min(first + chunk, count)) * hop
        yield every[at] * shape


def heard_bands(windowed, matrix):
    """Loudness in each band of each frame, as the listener the matrix was built for hears it.

    Loudness grows as about the cube root of power. Taking power straight through lets one loud
    frame set the median every threshold in bits() is taken against.
    """
    spectrum = numpy.abs(numpy.fft.rfft(windowed, axis=1)) ** 2
    return numpy.cbrt(spectrum @ matrix)


def envelope(loudness, terms=ENVELOPE_TERMS):
    """Each frame's spectral envelope, with the harmonic comb smoothed off it."""
    logged = numpy.log(loudness + TINY)
    coefficients = numpy.fft.rfft(logged, axis=1)
    coefficients[:, terms:] = 0.0
    return numpy.fft.irfft(coefficients, n=logged.shape[1], axis=1)


def segment_code(shape, bits=SEGMENT_BITS):
    """Each frame's envelope as numbers a change of speaker size does not move.

    A larger vocal tract scales every resonance by one factor. The bands are log spaced, so that
    scaling slides the whole envelope along the band axis without changing its shape, and the
    magnitude of a Fourier transform along that axis is unchanged by the slide. Coefficient 0 is
    the envelope's mean, which is loudness, and it goes to the prosody field instead.
    """
    return numpy.abs(numpy.fft.rfft(shape, axis=1))[:, 1:bits + 1]


def pitch(windowed, rate, low_hz=LOW_PITCH_HZ, high_hz=HIGH_PITCH_HZ):
    """Each frame's fundamental in Hz and how strongly it is voiced, both 0 where it is not.

    Autocorrelation and not the cepstrum. The bands above are log spaced, a harmonic comb is evenly
    spaced in Hz, and on a log axis that comb has no single quefrency to read a period off.
    """
    width = windowed.shape[1]
    # Autocorrelation through the frequency domain. Transforming at twice the width keeps the
    # wrap-around of a circular correlation out of the lags being searched.
    padded = numpy.fft.rfft(windowed, n=2 * width, axis=1)
    correlation = numpy.fft.irfft(padded * numpy.conj(padded), axis=1)[:, :width]
    energy = correlation[:, :1].copy()
    energy[energy <= 0.0] = 1.0
    correlation = correlation / energy
    shortest = max(1, int(round(rate / high_hz)))
    longest = min(width - 1, int(round(rate / low_hz)))
    if longest <= shortest:
        return numpy.zeros(windowed.shape[0]), numpy.zeros(windowed.shape[0])
    searched = correlation[:, shortest:longest + 1]
    at = searched.argmax(axis=1)
    strength = searched[numpy.arange(searched.shape[0]), at]
    period = (at + shortest) / float(rate)
    voiced = strength >= VOICED_AT
    return numpy.where(voiced, 1.0 / period, 0.0), numpy.where(voiced, strength, 0.0)


def prosody_code(measured):
    """Loudness, pitch against the speaker's own range, how that pitch is moving, and voicing.

    Against their own range and not against an absolute. A low voice and a high voice saying one
    stressed syllable have to reach one code, and what this field is asked for is where a frame
    sits inside the speaker, which is where stress is.

    measured holds one row per frame: the log of total loudness, the fundamental in Hz, and the
    voicing strength, in that order.
    """
    level = measured[:, 0]
    fundamental = measured[:, 1]
    voicing = measured[:, 2]
    spoken = fundamental[fundamental > 0.0]
    middle = numpy.median(spoken) if len(spoken) else 0.0
    relative = numpy.zeros(len(fundamental))
    if middle > 0.0:
        heard = fundamental > 0.0
        relative[heard] = numpy.log2(fundamental[heard] / middle)
    # In octaves against that median, so a rise of a fifth is one number whoever is speaking.
    moving = numpy.gradient(relative) if len(relative) > 1 else numpy.zeros(len(relative))
    return numpy.column_stack((level, relative, moving, voicing))


def bits(measured):
    """Each column of a measurement against its own median over the recording, as 0 or 1.

    The median and not a fixed threshold. One recording is one speaker in one room, and a constant
    picked off some other recording puts every frame of this one on the same side of it.
    """
    if not len(measured):
        return numpy.zeros((0, measured.shape[1]), dtype=numpy.uint8)
    middle = numpy.median(measured, axis=0)
    return (measured > middle).astype(numpy.uint8)


def decorrelated(measured):
    """One measurement rotated onto axes that do not vary together.

    Thresholding the columns as they come gives bits that repeat each other. Two neighboring bands
    rise and fall together, so their bits agree on nearly every frame and most of the codes never
    occur at all. Rotating onto the axes the measurement actually varies along, and cutting each of
    those at its median, is what brings the sample to the highest entropy it can carry: every bit
    splits the frames in half and no bit is another one restated. The states are then all reachable,
    and what the recording does against that is a difference worth measuring.

    The rotation is the right singular vectors of the centered measurement. A rotation adds no
    information and loses none; it moves the variation onto separate columns so the thresholds can
    reach it.
    """
    if len(measured) < 2:
        return measured
    centered = measured - measured.mean(axis=0)
    axes = numpy.linalg.svd(centered, full_matrices=False)[2]
    return centered @ axes.T


def code_profile(field):
    """A bit field as a distribution over the codes it takes, and how many frames that is.

    The shape anchor_sift.distance, support and entropy already read, so the delta against a
    maximum entropy reference is measured with the same functions the corpus work uses.
    """
    if not len(field):
        return {}, 0
    weights = (1 << numpy.arange(field.shape[1] - 1, -1, -1)).astype(numpy.int64)
    codes = field.astype(numpy.int64) @ weights
    seen, counts = numpy.unique(codes, return_counts=True)
    total = int(counts.sum())
    return {int(one): int(many) / total for one, many in zip(seen, counts)}, total


def represented(samples, rate, audiogram=NO_LOSS):
    """One recording as the time of each frame, its segment field, and its prosody field."""
    centers = band_centers()
    width = int(round(WINDOW_SECONDS * rate))
    matrix = band_matrix(width, rate, centers, band_gain(centers, audiogram))
    shapes = []
    raw = []
    for windowed in frame_chunks(samples, rate):
        loudness = heard_bands(windowed, matrix)
        shapes.append(segment_code(envelope(loudness)))
        fundamental, voicing = pitch(windowed, rate)
        raw.append(numpy.column_stack((numpy.log(loudness.sum(axis=1) + TINY),
                                       fundamental, voicing)))
    if not shapes:
        return (numpy.zeros(0), numpy.zeros((0, SEGMENT_BITS), dtype=numpy.uint8),
                numpy.zeros((0, PROSODY_BITS), dtype=numpy.uint8))
    # The median every threshold is taken against is the whole recording's, so the fields are cut
    # only once both are assembled. This is also where the speaker's own pitch range comes from.
    measured = numpy.concatenate(raw)
    at = numpy.arange(len(measured)) * HOP_SECONDS
    # The segment field is rotated first and the prosody field is not. The 24 segment coefficients
    # are anonymous and vary together, which is what decorrelated() is for. The four prosody
    # columns are each a named thing, and rotating them would mix pitch back into the field the
    # segment code was made shift invariant to get away from.
    return (at, bits(decorrelated(numpy.concatenate(shapes))),
            bits(prosody_code(measured)))
