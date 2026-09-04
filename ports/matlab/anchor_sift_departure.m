function value = anchor_sift_departure(seats, seed, min_occurrences)
% ANCHOR_SIFT_DEPARTURE  How far a sequence sits from a shuffle of itself.
%
%   value = anchor_sift_departure(seats)
%   value = anchor_sift_departure(seats, seed)
%   value = anchor_sift_departure(seats, seed, min_occurrences)
%
%   seats is a vector of symbols, for example double(uint8(text)).
%
%   A memoryless source returns about 1.00. Natural language returns 0.48 to 0.76. Below 1 means
%   the live sequence is more dispersed than its own shuffle, which is clustering.
%
%   This is a port of tools/dev_env/proof_conservation.py and computes the same number. Where the
%   two disagree the Python is the reference, because every figure in the ledger came out of it.
%
%   Runs unchanged on Octave.
%
%   anchor_sift - Copyright (C) 2026 Douglas Quigg (dstroy0) <dquigg123@gmail.com>
%   SPDX-License-Identifier: AGPL-3.0-or-later OR LicenseRef-Commercial OR LicenseRef-Educational

    if nargin < 2 || isempty(seed)
        seed = 0;
    end
    if nargin < 3 || isempty(min_occurrences)
        min_occurrences = 32;
    end

    seats = seats(:);

    [live_symbols, live_spread, counts] = local_dispersion(seats, min_occurrences);

    % The null. Same multiset, every position destroyed, which is the one background that cannot be
    % wrong about the property it removes because it is the data with that property gone.
    rand('seed', seed);                                     %#ok<RAND>
    shuffled = seats(randperm(numel(seats)));
    [dead_symbols, dead_spread] = local_dispersion(shuffled, min_occurrences);

    [shared, live_at, dead_at] = intersect(live_symbols, dead_symbols);
    keep = live_spread(live_at) > 0;
    shared = shared(keep);
    ratios = dead_spread(dead_at(keep)) ./ live_spread(live_at(keep));

    if numel(shared) < 4
        value = NaN;
        return;
    end

    % Sorted by how often each symbol occurs, most frequent first, then the back half taken. That
    % back half is the rare half and it is the only part quoted anywhere in this work. The frequent
    % half tracks corpus length and is not comparable between corpora of different sizes.
    [~, shared_at] = ismember(shared, live_symbols);
    [~, order_by_count] = sort(counts(shared_at), 'descend');
    ranked = ratios(order_by_count);
    value = mean(ranked(floor(numel(ranked) / 2) + 1 : end));
end


function [symbols, spread, counts] = local_dispersion(seats, min_occurrences)
% Coefficient of variation of the gaps between occurrences, one value per symbol.
    symbols = unique(seats);
    spread = zeros(numel(symbols), 1);
    counts = zeros(numel(symbols), 1);
    keep = false(numel(symbols), 1);

    for at = 1:numel(symbols)
        where = find(seats == symbols(at));
        counts(at) = numel(where);
        if numel(where) < min_occurrences
            continue;
        end
        gaps = diff(where);
        middle = mean(gaps);
        if middle > 0
            % Population standard deviation, matching Python's statistics.pstdev. MATLAB's std
            % divides by n-1 by default, and the second argument switches it to n.
            spread(at) = std(gaps, 1) / middle;
            keep(at) = true;
        end
    end

    symbols = symbols(keep);
    spread = spread(keep);
    counts = counts(keep);
end
