function result = extractCarPlateFromImage(inputValue, varargin)
%EXTRACTCARPLATEFROMIMAGE Try multiple plate detectors in fallback order.
% The default order is v4, then v2, then v1, then v3. A result is accepted as soon
% as the OCR text looks plate-like for common Malaysian formats.

    %#ok<*INUSD>

    detectorOrder = { ...
        'v4', @extractCarPlateFromImage_v4
        'v2', @extractCarPlateFromImage_v2
        'v1', @extractCarPlateFromImage_v1
        'v3', @extractCarPlateFromImage_v3
    };

    attempts = strings(0, 1);
    fallbackResult = struct([]);
    debugAttempts = repmat(makeMethodDebugAttempt(""), 0, 1);

    for i = 1:size(detectorOrder, 1)
        methodName = string(detectorOrder{i, 1});
        detectorFn = detectorOrder{i, 2};
        attempts(end + 1, 1) = methodName; %#ok<AGROW>

        try
            currentResult = detectorFn(inputValue);
        catch detectorError
            debugAttempts(end + 1, 1) = buildErrorDebugAttempt(methodName, detectorError); %#ok<AGROW>
            continue;
        end

        currentResult = applyRescueCropOCR(currentResult);
        currentResult = enrichResult(currentResult, methodName, attempts);
        debugAttempts(end + 1, 1) = extractMethodDebugAttempt(currentResult, methodName); %#ok<AGROW>
        if isAcceptableFinalResult(currentResult)
            currentResult.DebugReport = buildAggregateDebugReport(debugAttempts, attempts, methodName);
            result = currentResult;
            return;
        end

        if isempty(fallbackResult)
            fallbackResult = currentResult;
        elseif isBetterFallback(currentResult, fallbackResult)
            fallbackResult = currentResult;
        end
    end

    if isempty(fallbackResult)
        imageData = readInputImage(inputValue);
        fallbackResult = struct( ...
            'Image', imageData, ...
            'PlateText', "", ...
            'PlateBox', [], ...
            'PlateImage', [], ...
            'BinaryPlate', [], ...
            'CandidateBoxes', zeros(0, 4), ...
            'DebugReport', struct());
    end

    if isfield(fallbackResult, 'MethodUsed')
        bestMethod = fallbackResult.MethodUsed;
    else
        bestMethod = "none";
    end

    result = enrichResult(fallbackResult, bestMethod, attempts);
    result.DebugReport = buildAggregateDebugReport(debugAttempts, attempts, bestMethod);
end

function result = enrichResult(result, methodName, attempts)
    if nargin < 3
        attempts = string(methodName);
    end

    result.PlateText = applyLeadingLetterBias(string(result.PlateText));
    result.MethodUsed = string(methodName);
    result.AttemptedMethods = string(attempts(:)');
    result.IsPlateTextValid = isAcceptableFinalResult(result);
end

function tf = isBetterFallback(candidate, currentBest)
    candidateScore = fallbackResultScore(candidate);
    currentScore = fallbackResultScore(currentBest);
    tf = candidateScore > currentScore;
end

function score = fallbackResultScore(result)
    plateText = cleanPlateText(result.PlateText);
    score = strlength(plateText) * 10;

    if isAcceptableFinalPlateText(plateText)
        score = score + 220;
    elseif isUsablePlateText(plateText)
        score = score + 40;
    else
        score = score - 80;
    end

    if ~isempty(result.PlateBox)
        if isUsablePlateText(plateText)
            score = score + 18;
        else
            score = score + 2;
        end
    end
    if ~isempty(result.PlateImage)
        if isUsablePlateText(plateText)
            score = score + 12;
        end
    end
    if ~isempty(result.CandidateBoxes)
        if isUsablePlateText(plateText)
            score = score + min(size(result.CandidateBoxes, 1), 8);
        else
            score = score - min(size(result.CandidateBoxes, 1), 8);
        end
    end
end

function tf = isValidPlateText(textValue)
    tf = isAcceptableFinalPlateText(textValue);
end

function tf = isAcceptableFinalResult(result)
    if ~isAcceptableFinalPlateText(result.PlateText)
        tf = false;
        return;
    end

    tf = passesFallbackSanity(result) || isDetectorAcceptedReliableRead(result);
end

function tf = passesFallbackSanity(result)
    tf = false;
    if ~isfield(result, 'PlateImage') || isempty(result.PlateImage)
        return;
    end

    plateImage = result.PlateImage;
    if ndims(plateImage) == 3
        plateImage = rgb2gray(plateImage);
    end
    plateImage = im2uint8(plateImage);

    if size(plateImage, 1) < 16 || size(plateImage, 2) < 32
        return;
    end

    if hasStrongPlateEvidence(result.PlateText, plateImage)
        tf = true;
        return;
    end

    if std2(plateImage) < 12
        return;
    end

    darkMask = imbinarize(plateImage, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.45);
    brightMask = imbinarize(plateImage, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
    binaryMask = darkMask | brightMask;
    binaryMask = bwareaopen(binaryMask, 12);
    fgRatio = nnz(binaryMask) / numel(binaryMask);
    if fgRatio < 0.02 || fgRatio > 0.65
        return;
    end

    cc = bwconncomp(binaryMask);
    stats = regionprops(cc, 'BoundingBox', 'Area');
    if isempty(stats)
        return;
    end
    boxes = reshape([stats.BoundingBox], 4, []).';
    areas = [stats.Area]';
    heights = boxes(:, 4);
    widths = boxes(:, 3);
    aspect = widths ./ max(heights, 1);
    keep = areas > 10 & areas < 6000 & aspect > 0.08 & aspect < 1.6;
    if sum(keep) < 3
        return;
    end

    tf = true;
end

function tf = hasStrongPlateEvidence(plateText, plateImage)
    tf = false;
    cleanedText = cleanPlateText(plateText);
    if ~isAcceptableFinalPlateText(cleanedText)
        return;
    end

    if std2(plateImage) < 8
        return;
    end

    darkMask = imbinarize(plateImage, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    brightMask = imbinarize(plateImage, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.50);
    binaryMask = darkMask | brightMask;
    binaryMask = bwareaopen(binaryMask, 8);

    fgRatio = nnz(binaryMask) / numel(binaryMask);
    if fgRatio < 0.015 || fgRatio > 0.72
        return;
    end

    cc = bwconncomp(binaryMask);
    stats = regionprops(cc, 'BoundingBox', 'Area');
    if isempty(stats)
        return;
    end

    boxes = reshape([stats.BoundingBox], 4, []).';
    areas = [stats.Area]';
    heights = boxes(:, 4);
    widths = boxes(:, 3);
    aspect = widths ./ max(heights, 1);
    keep = areas > 8 & areas < 8000 & heights >= 4 & widths >= 2 & aspect > 0.06 & aspect < 1.8;

    minComponents = max(2, min(4, countLetterDigitTransitions(cleanedText)));
    tf = sum(keep) >= minComponents;
end

function tf = isDetectorAcceptedReliableRead(result)
    tf = false;
    if ~isfield(result, 'DebugReport') || isempty(result.DebugReport) || ...
            ~isfield(result.DebugReport, 'Status') || ...
            ~strcmpi(char(string(result.DebugReport.Status)), 'completed')
        return;
    end

    cleanedText = cleanPlateText(result.PlateText);
    if strlength(cleanedText) < 6
        if ~isempty(regexp(char(cleanedText), '^Z[A-Z]\d{1,4}$', 'once'))
            tf = true;
        end
        return;
    end

    if ~isfield(result, 'PlateBox') || isempty(result.PlateBox) || ...
            ~isfield(result, 'PlateImage') || isempty(result.PlateImage)
        return;
    end

    tf = scoreRescuePlateText(cleanedText) >= 120;
end

function tf = isAcceptableFinalPlateText(textValue)
    cleanedText = cleanPlateText(textValue);

    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        tf = false;
        return;
    end

    hasAlpha = any(isstrprop(char(cleanedText), 'alpha'));
    hasDigit = any(isstrprop(char(cleanedText), 'digit'));
    if ~(hasAlpha && hasDigit)
        tf = false;
        return;
    end

    if strlength(cleanedText) >= 4 && ...
            ~isempty(regexp(char(cleanedText), ...
            '^\d{2,4}(DC|CC|UN|PA)$|^Z[A-Z]\d{1,4}$|^[A-Z]{1,3}\d{1,4}[A-Z]?$', 'once'))
        tf = true;
        return;
    end

    tf = ~isempty(regexp(char(cleanedText), '^[A-Z]\d{2,4}$', 'once'));
end

function tf = isUsablePlateText(textValue)
    cleanedText = cleanPlateText(textValue);

    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        tf = false;
        return;
    end

    hasAlpha = any(isstrprop(char(cleanedText), 'alpha'));
    hasDigit = any(isstrprop(char(cleanedText), 'digit'));
    tf = hasAlpha && hasDigit;
end

function cleanedText = cleanPlateText(textValue)
    cleanedText = upper(string(textValue));
    cleanedText = regexprep(cleanedText, '[^A-Z0-9]', '');
end

function transitionCount = countLetterDigitTransitions(textValue)
    cleanedText = cleanPlateText(textValue);
    transitionCount = 0;
    if strlength(cleanedText) < 2
        return;
    end

    textChars = char(cleanedText);
    for i = 2:numel(textChars)
        prevIsAlpha = isstrprop(textChars(i - 1), 'alpha');
        currIsAlpha = isstrprop(textChars(i), 'alpha');
        if prevIsAlpha ~= currIsAlpha
            transitionCount = transitionCount + 1;
        end
    end
end

function textValue = applyLeadingLetterBias(textValue)
    textValue = cleanPlateText(textValue);
    if strlength(textValue) < 2 || extractBetween(textValue, 1, 1) ~= "U"
        return;
    end

    firstDigitIndex = regexp(char(textValue), '\d', 'once');
    if isempty(firstDigitIndex) || firstDigitIndex <= 1
        return;
    end

    prefix = extractBefore(textValue, firstDigitIndex);
    if strlength(prefix) > 3
        return;
    end

    biasedCandidate = "V" + extractAfter(textValue, 1);
    originalScore = scoreLeadingLetterBiasCandidate(textValue);
    biasedScore = scoreLeadingLetterBiasCandidate(biasedCandidate) + 6;

    if biasedScore > originalScore
        textValue = biasedCandidate;
    end
end

function score = scoreLeadingLetterBiasCandidate(textValue)
    cleanedText = cleanPlateText(textValue);
    score = scoreRescuePlateText(cleanedText);

    if ~isempty(regexp(char(cleanedText), '^[A-Z]{1,3}\d{1,4}[A-Z]?$', 'once'))
        score = score + 4;
    end

    if startsWith(cleanedText, "V")
        score = score + 2;
    elseif startsWith(cleanedText, "U")
        score = score - 4;
    end
end

function result = applyRescueCropOCR(result)
    if ~isfield(result, 'PlateImage') || isempty(result.PlateImage)
        return;
    end

    [rescueText, rescueBinary, rescueScore] = rescueCropOCR(result.PlateImage);
    currentText = "";
    if isfield(result, 'PlateText')
        currentText = string(result.PlateText);
    end

    currentScore = scoreRescuePlateText(currentText);
    if rescueScore <= currentScore
        return;
    end

    result.PlateText = rescueText;
    if ~isempty(rescueBinary)
        result.BinaryPlate = rescueBinary;
    end
end

function [bestText, bestBinary, bestScore] = rescueCropOCR(plateImage)
    bestText = "";
    bestBinary = [];
    bestScore = -inf;

    if isempty(plateImage)
        return;
    end

    if ndims(plateImage) == 3
        grayImage = rgb2gray(plateImage);
    else
        grayImage = plateImage;
    end

    grayImage = im2uint8(grayImage);
    enhanced = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.02);
    sharpened = imsharpen(enhanced, 'Radius', 1.0, 'Amount', 1.0);
    contrastBoost = imadjust(grayImage, stretchlim(grayImage, [0.01 0.995]), []);
    gammaBright = imadjust(enhanced, [], [], 0.85);
    gammaDark = imadjust(enhanced, [], [], 1.20);
    trimmedGray = trimPlateBorderForRescue(grayImage);
    trimmedSharp = trimPlateBorderForRescue(sharpened);
    paddedGray = padPlateCropForRescue(grayImage);
    paddedSharp = padPlateCropForRescue(sharpened);
    leftPaddedGray = padPlateCropForRescue(grayImage, true);
    leftPaddedSharp = padPlateCropForRescue(sharpened, true);
    upscaled2 = imresize(sharpened, 2.0, 'bicubic');
    upscaled3 = imresize(sharpened, 3.0, 'bicubic');
    darkText = cleanRescueBinary(imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42));
    brightText = cleanRescueBinary(imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48));
    invertedImage = imcomplement(sharpened);

    variants = { ...
        grayImage, enhanced, sharpened, contrastBoost, gammaBright, gammaDark, trimmedGray, trimmedSharp, ...
        paddedGray, paddedSharp, leftPaddedGray, leftPaddedSharp, ...
        darkText, brightText, invertedImage, upscaled2, upscaled3};
    for i = 1:numel(variants)
        currentVariant = variants{i};
        currentInput = im2uint8(currentVariant);
        [candidateText, candidateScore] = rescueReadVariant(currentInput);
        if candidateScore > bestScore
            bestScore = candidateScore;
            bestText = candidateText;
            if islogical(currentVariant)
                bestBinary = currentVariant;
            else
                bestBinary = cleanRescueBinary(imbinarize(currentInput, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42));
            end
        end
    end
end

function [bestText, bestScore] = rescueReadVariant(ocrInput)
    candidates = strings(0, 1);
    scores = [];

    try
        result = ocr(ocrInput, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Word');
        textValue = normalizeRescueOCRText(result.Text);
        candidates(end + 1, 1) = textValue; %#ok<AGROW>
        scores(end + 1, 1) = scoreRescuePlateText(textValue) + mean(result.CharacterConfidences, 'omitnan') / 5; %#ok<AGROW>

        [militaryText, militaryScore] = rescueMilitaryFromSplitOCR(ocrInput);
        if strlength(militaryText) > 0
            candidates(end + 1, 1) = militaryText; %#ok<AGROW>
            scores(end + 1, 1) = militaryScore + mean(result.CharacterConfidences, 'omitnan') / 8; %#ok<AGROW>
        end

        militaryDigitCandidates = rescueMilitaryDigitReOCR(textValue, ocrInput);
        if isempty(militaryDigitCandidates) && strlength(militaryText) > 0
            militaryDigitCandidates = rescueMilitaryDigitReOCR(militaryText, ocrInput);
        end
        for variantIndex = 1:numel(militaryDigitCandidates)
            variantText = militaryDigitCandidates(variantIndex);
            candidates(end + 1, 1) = variantText; %#ok<AGROW>
            scores(end + 1, 1) = scoreRescuePlateText(variantText) + 32; %#ok<AGROW>
        end

        [stackedText, stackedScore] = rescueStackedCivilianFromSplitOCR(ocrInput);
        if strlength(stackedText) > 0
            candidates(end + 1, 1) = stackedText; %#ok<AGROW>
            scores(end + 1, 1) = stackedScore + mean(result.CharacterConfidences, 'omitnan') / 8; %#ok<AGROW>
        end
    catch
    end

    try
        result = ocr(ocrInput, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Block');
        textValue = normalizeRescueOCRText(result.Text);
        candidates(end + 1, 1) = textValue; %#ok<AGROW>
        scores(end + 1, 1) = scoreRescuePlateText(textValue) + mean(result.CharacterConfidences, 'omitnan') / 5; %#ok<AGROW>
    catch
    end

    if size(ocrInput, 1) >= size(ocrInput, 2) * 0.55
        rows = size(ocrInput, 1);
        topHalf = ocrInput(1:max(1, round(rows * 0.58)), :);
        bottomHalf = ocrInput(max(1, round(rows * 0.34)):end, :);
        try
            topResult = ocr(topHalf, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Block');
            bottomResult = ocr(bottomHalf, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Block');
            textValue = normalizeRescueOCRText(cleanPlateText(topResult.Text) + cleanPlateText(bottomResult.Text));
            candidates(end + 1, 1) = textValue; %#ok<AGROW>
            scores(end + 1, 1) = scoreRescuePlateText(textValue) + 24; %#ok<AGROW>
        catch
        end
    end

    if isempty(scores)
        bestText = "";
        bestScore = -inf;
        return;
    end

    [bestScore, idx] = max(scores);
    bestText = candidates(idx);
end

function [bestText, bestScore] = rescueStackedCivilianFromSplitOCR(ocrInput)
    bestText = "";
    bestScore = -inf;
    if isempty(ocrInput)
        return;
    end

    aspectRatio = size(ocrInput, 2) / max(size(ocrInput, 1), 1);
    if aspectRatio < 0.55 || aspectRatio > 1.9
        return;
    end

    rows = size(ocrInput, 1);
    splitRows = unique(max(2, min(rows - 1, round(rows * [0.44 0.50 0.56]))));
    for splitRow = splitRows
        topHalf = ocrInput(1:splitRow, :);
        bottomHalf = ocrInput(splitRow:end, :);

        topCandidates = readCivilianPrefixCandidates(topHalf);
        bottomCandidates = readCivilianDigitCandidates(bottomHalf);
        for i = 1:numel(topCandidates)
            for j = 1:numel(bottomCandidates)
                candidate = cleanPlateText(topCandidates(i) + bottomCandidates(j));
                if isempty(regexp(char(candidate), '^[A-Z]{1,3}\d{1,4}$', 'once'))
                    continue;
                end
                currentScore = scoreRescuePlateText(candidate) + 26;
                if strlength(candidate) >= 6
                    currentScore = currentScore + 12;
                end
                if currentScore > bestScore
                    bestScore = currentScore;
                    bestText = candidate;
                end
            end
        end
    end
end

function candidates = readCivilianPrefixCandidates(imagePart)
    rawReads = strings(0, 1);
    partVariants = {im2uint8(imagePart), imresize(im2uint8(imagePart), 2.0, 'bicubic')};

    for i = 1:numel(partVariants)
        currentPart = partVariants{i};
        try
            result = ocr(currentPart, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ', 'TextLayout', 'Word');
            rawReads(end + 1, 1) = cleanPlateText(result.Text); %#ok<AGROW>
        catch
        end
        try
            result = ocr(currentPart, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Word');
            rawReads(end + 1, 1) = cleanPlateText(result.Text); %#ok<AGROW>
        catch
        end
    end

    candidates = strings(0, 1);
    for i = 1:numel(rawReads)
        current = cleanPlateText(rawReads(i));
        current = regexprep(current, '[^A-Z]', '');
        if strlength(current) >= 1
            candidates(end + 1, 1) = extractBefore(current + " ", min(strlength(current), 3) + 1); %#ok<AGROW>
        end
    end
    candidates = unique(candidates);
end

function candidates = readCivilianDigitCandidates(imagePart)
    rawReads = strings(0, 1);
    partVariants = {im2uint8(imagePart), imresize(im2uint8(imagePart), 2.0, 'bicubic')};

    for i = 1:numel(partVariants)
        currentPart = partVariants{i};
        try
            result = ocr(currentPart, 'CharacterSet', '0123456789', 'TextLayout', 'Word');
            rawReads(end + 1, 1) = cleanPlateText(result.Text); %#ok<AGROW>
        catch
        end
        try
            result = ocr(currentPart, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Word');
            rawReads(end + 1, 1) = cleanPlateText(result.Text); %#ok<AGROW>
        catch
        end
    end

    candidates = strings(0, 1);
    for i = 1:numel(rawReads)
        current = cleanPlateText(rawReads(i));
        current = regexprep(current, '[^0-9]', '');
        if strlength(current) >= 2
            if strlength(current) > 4
                candidates(end + 1, 1) = extractAfter(current, strlength(current) - 4); %#ok<AGROW>
            else
                candidates(end + 1, 1) = current; %#ok<AGROW>
            end
        end
    end
    candidates = unique(candidates);
end

function textValue = normalizeRescueOCRText(rawText)
    textValue = cleanPlateText(rawText);
    if strlength(textValue) == 0
        return;
    end

    candidates = unique(string({
        char(textValue)
        strrep(char(textValue), 'O', '0')
        strrep(char(textValue), '0', 'O')
        strrep(char(textValue), 'I', '1')
        strrep(char(textValue), '1', 'I')
        strrep(char(textValue), 'B', '8')
        strrep(char(textValue), '8', 'B')
        strrep(char(textValue), 'S', '5')
        strrep(char(textValue), '5', 'S')
        strrep(char(textValue), 'Z', '2')
        strrep(char(textValue), '2', 'Z')
    }));

    bestCandidate = textValue;
    bestScore = -inf;
    for i = 1:numel(candidates)
        current = cleanPlateText(candidates(i));
        current = extractBestRescueSubstring(current);
        currentScore = scoreRescuePlateText(current);
        if currentScore > bestScore
            bestScore = currentScore;
            bestCandidate = current;
        end
    end

    textValue = applyLeadingLetterBias(bestCandidate);
end

function trimmedImage = trimPlateBorderForRescue(imageData)
    trimmedImage = imageData;
    if isempty(imageData)
        return;
    end

    trimY = max(1, round(size(imageData, 1) * 0.05));
    trimX = max(1, round(size(imageData, 2) * 0.04));
    if size(imageData, 1) > 2 * trimY && size(imageData, 2) > 2 * trimX
        trimmedImage = imageData((1 + trimY):(end - trimY), (1 + trimX):(end - trimX), :);
    end
end

function paddedImage = padPlateCropForRescue(imageData, emphasizeLeft)
    if nargin < 2
        emphasizeLeft = false;
    end

    paddedImage = imageData;
    if isempty(imageData)
        return;
    end

    imageData = im2uint8(imageData);
    padY = max(2, round(size(imageData, 1) * 0.08));
    padLeft = max(3, round(size(imageData, 2) * 0.10));
    padRight = max(2, round(size(imageData, 2) * 0.06));
    if emphasizeLeft
        padLeft = max(padLeft, round(size(imageData, 2) * 0.16));
        padRight = max(2, round(size(imageData, 2) * 0.04));
    end
    fillValue = median(imageData(:));
    paddedImage = padarray(imageData, [padY padLeft], fillValue, 'both');
    if padRight > padLeft
        paddedImage = padarray(paddedImage, [0 padRight - padLeft], fillValue, 'post');
    elseif padRight < padLeft
        paddedImage = paddedImage(:, 1:(end - (padLeft - padRight)));
    end
end

function [bestText, bestScore] = rescueMilitaryFromSplitOCR(ocrInput)
    bestText = "";
    bestScore = -inf;
    if isempty(ocrInput) || size(ocrInput, 2) < 24
        return;
    end

    cols = size(ocrInput, 2);
    splitCol = max(8, round(cols * 0.38));
    leftPart = ocrInput(:, 1:splitCol);
    rightPart = ocrInput(:, max(1, round(cols * 0.28)):end);

    leftCandidates = readRescuePartCandidates(leftPart, true);
    rightCandidates = readRescuePartCandidates(rightPart, false);
    if isempty(leftCandidates) || isempty(rightCandidates)
        return;
    end

    for i = 1:numel(leftCandidates)
        for j = 1:numel(rightCandidates)
            candidate = cleanPlateText(leftCandidates(i) + rightCandidates(j));
            if isempty(regexp(char(candidate), '^Z[A-Z]\d{1,4}$', 'once'))
                continue;
            end
            currentScore = scoreRescuePlateText(candidate) + 28;
            if currentScore > bestScore
                bestScore = currentScore;
                bestText = candidate;
            end
        end
    end
end

function candidates = readRescuePartCandidates(partImage, expectLetters)
    candidates = strings(0, 1);
    if isempty(partImage)
        return;
    end

    try
        result = ocr(im2uint8(partImage), 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Word');
        rawText = cleanPlateText(result.Text);
    catch
        rawText = "";
    end

    if strlength(rawText) == 0
        return;
    end

    if expectLetters
        candidates = normalizeMilitaryPrefixCandidates(rawText);
    else
        candidates = normalizeMilitaryDigitCandidates(rawText);
    end
end

function candidates = normalizeMilitaryPrefixCandidates(rawText)
    rawText = cleanPlateText(rawText);
    variants = unique(string({
        char(rawText)
        strrep(char(rawText), '2', 'Z')
        strrep(char(rawText), '7', 'Z')
        strrep(char(rawText), 'T', 'Z')
        strrep(char(rawText), 'I', 'Z')
        strrep(char(rawText), '1', 'I')
    }));

    candidates = strings(0, 1);
    for i = 1:numel(variants)
        current = cleanPlateText(variants(i));
        current = regexprep(current, '[^A-Z]', '');
        if strlength(current) >= 1
            candidates(end + 1, 1) = extractBefore(current + " ", min(strlength(current), 2) + 1); %#ok<AGROW>
        end
    end
    candidates = unique(candidates);
end

function candidates = normalizeMilitaryDigitCandidates(rawText)
    rawText = cleanPlateText(rawText);
    variants = unique(string({
        char(rawText)
        strrep(char(rawText), 'O', '0')
        strrep(char(rawText), 'I', '1')
        strrep(char(rawText), 'L', '1')
        strrep(char(rawText), 'Z', '2')
        strrep(char(rawText), 'S', '5')
        strrep(char(rawText), 'B', '8')
    }));

    candidates = strings(0, 1);
    for i = 1:numel(variants)
        current = cleanPlateText(variants(i));
        current = regexprep(current, '[^0-9]', '');
        if strlength(current) >= 3
            if strlength(current) > 4
                candidates(end + 1, 1) = extractAfter(current, strlength(current) - 4); %#ok<AGROW>
            else
                candidates(end + 1, 1) = current; %#ok<AGROW>
            end
        end
    end
    candidates = unique(candidates);
end

function candidates = rescueMilitaryDigitReOCR(textValue, ocrInput)
    candidates = strings(0, 1);
    cleanedText = cleanPlateText(textValue);
    if isempty(regexp(char(cleanedText), '^Z[A-Z]\d{2,4}$', 'once'))
        return;
    end
    if isempty(ocrInput) || size(ocrInput, 2) < 40 || size(ocrInput, 1) < 12
        return;
    end

    digitChars = char(extractAfter(cleanedText, 2));
    expectedDigits = numel(digitChars);

    digitBoxes = locateRescueMilitaryDigitBoxes(ocrInput, expectedDigits);
    if isempty(digitBoxes)
        return;
    end

    grayInput = im2uint8(ocrInput);
    if ndims(grayInput) == 3
        grayInput = rgb2gray(grayInput);
    end

    perDigitText = repmat(' ', 1, expectedDigits);
    for k = 1:expectedDigits
        digitImage = cropPaddedRescueDigit(grayInput, digitBoxes(k, :));
        if isempty(digitImage)
            return;
        end
        digitChar = readSingleRescueDigit(digitImage);
        if isempty(digitChar)
            return;
        end
        perDigitText(k) = digitChar;
    end

    if any(perDigitText == ' ') || ~all(isstrprop(perDigitText, 'digit'))
        return;
    end

    rebuilt = string(extractBefore(cleanedText, 3)) + string(perDigitText);
    if rebuilt ~= string(cleanedText)
        candidates(end + 1, 1) = rebuilt;
    end
end

function digitBoxes = locateRescueMilitaryDigitBoxes(ocrInput, expectedDigits)
    digitBoxes = [];
    if islogical(ocrInput)
        binaryMask = ocrInput;
    else
        grayInput = im2uint8(ocrInput);
        if ndims(grayInput) == 3
            grayInput = rgb2gray(grayInput);
        end
        darkMask = imbinarize(grayInput, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
        brightMask = imbinarize(grayInput, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
        binaryMask = darkMask | brightMask;
    end
    binaryMask = cleanRescueBinary(binaryMask);
    if ~any(binaryMask(:))
        return;
    end

    [rows, cols] = size(binaryMask);
    stats = regionprops(binaryMask, 'BoundingBox', 'Area');
    if isempty(stats)
        return;
    end

    boxes = reshape([stats.BoundingBox], 4, []).';
    areas = [stats.Area]';
    widths = boxes(:, 3);
    heights = boxes(:, 4);
    aspect = widths ./ max(heights, 1);

    keep = areas >= 18 & ...
        heights >= rows * 0.28 & heights <= rows * 0.95 & ...
        widths >= 2 & widths <= cols * 0.45 & ...
        aspect >= 0.08 & aspect <= 1.4;
    boxes = boxes(keep, :);

    if size(boxes, 1) < expectedDigits
        return;
    end

    [~, order] = sort(boxes(:, 1));
    boxes = boxes(order, :);

    digitOnly = boxes(boxes(:, 1) >= cols * 0.18, :);
    if size(digitOnly, 1) < expectedDigits
        digitOnly = boxes(end - expectedDigits + 1:end, :);
    elseif size(digitOnly, 1) > expectedDigits
        digitOnly = digitOnly(end - expectedDigits + 1:end, :);
    end

    if size(digitOnly, 1) ~= expectedDigits
        return;
    end

    digitBoxes = digitOnly;
end

function digitImage = cropPaddedRescueDigit(grayInput, bbox)
    digitImage = [];
    if isempty(bbox)
        return;
    end
    [rows, cols] = size(grayInput);
    padX = max(2, round(bbox(3) * 0.30));
    padY = max(2, round(bbox(4) * 0.20));
    x1 = max(1, floor(bbox(1) - padX));
    y1 = max(1, floor(bbox(2) - padY));
    x2 = min(cols, ceil(bbox(1) + bbox(3) + padX));
    y2 = min(rows, ceil(bbox(2) + bbox(4) + padY));
    if x2 <= x1 || y2 <= y1
        return;
    end
    digitImage = grayInput(y1:y2, x1:x2);
end

function digitChar = readSingleRescueDigit(digitImage)
    digitChar = '';
    if isempty(digitImage)
        return;
    end

    upscaled = imresize(digitImage, 5.0, 'bicubic');
    upscaled = im2uint8(upscaled);
    sharpened = imsharpen(upscaled, 'Radius', 1.0, 'Amount', 1.4);
    enhanced = adapthisteq(upscaled, 'NumTiles', [4 4], 'ClipLimit', 0.02);
    fillValue = median(upscaled(:));
    paddedSharp = padarray(sharpened, [10 10], fillValue, 'both');
    paddedEnh = padarray(enhanced, [10 10], fillValue, 'both');

    candidatesList = {paddedSharp, paddedEnh, sharpened};
    layouts = {'Character', 'Word', 'Block'};

    bestChar = '';
    bestConfidence = -inf;
    for variantIdx = 1:numel(candidatesList)
        ocrInput = candidatesList{variantIdx};
        for layoutIdx = 1:numel(layouts)
            try
                ocrResult = ocr(ocrInput, ...
                    'CharacterSet', '0123456789', ...
                    'TextLayout', layouts{layoutIdx});
            catch
                continue;
            end
            cleaned = regexprep(upper(string(ocrResult.Text)), '[^0-9]', '');
            if strlength(cleaned) == 0
                continue;
            end
            firstChar = char(extractBefore(cleaned + " ", 2));
            if ~isempty(ocrResult.CharacterConfidences)
                confidence = mean(ocrResult.CharacterConfidences, 'omitnan');
            else
                confidence = 0;
            end
            if confidence > bestConfidence
                bestConfidence = confidence;
                bestChar = firstChar;
            end
        end
    end

    digitChar = bestChar;
end

function bestText = extractBestRescueSubstring(rawText)
    bestText = string(rawText);
    if strlength(bestText) == 0
        return;
    end

    matches = regexp(char(bestText), '\d{2,4}(DC|CC|UN|PA)|Z[A-Z]\d{1,4}|[A-Z]{1,3}\d{1,4}[A-Z]?', 'match');
    if isempty(matches)
        matches = {char(bestText)};
    end

    bestScore = -inf;
    for i = 1:numel(matches)
        candidate = string(matches{i});
        currentScore = scoreRescuePlateText(candidate);
        if currentScore > bestScore
            bestScore = currentScore;
            bestText = candidate;
        end
    end
end

function score = scoreRescuePlateText(textValue)
    cleanedText = cleanPlateText(textValue);
    score = strlength(cleanedText) * 8;

    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        score = score - 200;
        return;
    end

    if any(isstrprop(char(cleanedText), 'alpha')) && any(isstrprop(char(cleanedText), 'digit'))
        score = score + 18;
    else
        score = score - 90;
    end

    if ~isempty(regexp(char(cleanedText), '^Z[A-Z]\d{1,4}$', 'once'))
        score = score + 80;
    elseif ~isempty(regexp(char(cleanedText), '^[A-Z]{1,3}\d{1,4}[A-Z]?$', 'once'))
        score = score + 52;
    elseif ~isempty(regexp(char(cleanedText), '^\d{2,4}(DC|CC|UN|PA)$', 'once'))
        score = score + 52;
    elseif ~isempty(regexp(char(cleanedText), '^[A-Z]\d{2,4}$', 'once'))
        score = score + 18;
    else
        score = score - 45;
    end

    if ~isempty(regexp(char(cleanedText), '^[A-Z]\d[A-Z]{2,3}$', 'once'))
        score = score - 55;
    elseif ~isempty(regexp(char(cleanedText), '^[A-Z]{1,2}\d[A-Z]{2,3}$', 'once'))
        score = score - 35;
    end
end

function binaryImage = cleanRescueBinary(binaryImage)
    binaryImage = logical(binaryImage);
    binaryImage = imclearborder(binaryImage);
    binaryImage = bwareaopen(binaryImage, 8);
    binaryImage = imclose(binaryImage, strel('rectangle', [2 2]));
end

function imageData = readInputImage(inputValue)
    if ischar(inputValue) || isstring(inputValue)
        imageData = imread(char(inputValue));
    else
        imageData = inputValue;
    end
end

function aggregate = buildAggregateDebugReport(debugAttempts, attempts, selectedMethod)
    aggregate = struct( ...
        'Type', "fallback-debug-report", ...
        'SelectedMethod', string(selectedMethod), ...
        'AttemptedMethods', string(attempts(:)'), ...
        'Attempts', debugAttempts);
end

function debugAttempt = extractMethodDebugAttempt(result, methodName)
    debugAttempt = makeMethodDebugAttempt(methodName);
    if isfield(result, 'DebugReport') && ~isempty(result.DebugReport)
        debugAttempt = result.DebugReport;
        if ~isfield(debugAttempt, 'Method') || strlength(string(debugAttempt.Method)) == 0
            debugAttempt.Method = string(methodName);
        end
        if ~isfield(debugAttempt, 'Status') || strlength(string(debugAttempt.Status)) == 0
            debugAttempt.Status = "completed";
        end
        if ~isfield(debugAttempt, 'Notes')
            debugAttempt.Notes = "";
        end
        if ~isfield(debugAttempt, 'Steps')
            debugAttempt.Steps = repmat(makeDebugStep("", [], ""), 0, 1);
        end
    else
        debugAttempt.Status = "completed";
        debugAttempt.Notes = "Detector returned without a detailed debug payload.";
    end
end

function debugAttempt = buildErrorDebugAttempt(methodName, detectorError)
    debugAttempt = makeMethodDebugAttempt(methodName);
    debugAttempt.Status = "error";
    debugAttempt.Notes = string(detectorError.message);
    debugAttempt.Steps = makeDebugStep("Method error", [], detectorError.message);
end

function debugAttempt = makeMethodDebugAttempt(methodName)
    debugAttempt = struct( ...
        'Method', string(methodName), ...
        'Status', "not-run", ...
        'Notes', "", ...
        'Steps', repmat(makeDebugStep("", [], ""), 0, 1));
end

function step = makeDebugStep(titleText, imageData, descriptionText)
    step = struct( ...
        'Title', string(titleText), ...
        'Image', imageData, ...
        'Description', string(descriptionText));
end
