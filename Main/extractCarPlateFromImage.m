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

    result.PlateText = string(result.PlateText);
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
    tf = isAcceptableFinalPlateText(result.PlateText) && passesFallbackSanity(result);
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
    upscaled2 = imresize(sharpened, 2.0, 'bicubic');
    upscaled3 = imresize(sharpened, 3.0, 'bicubic');
    darkText = cleanRescueBinary(imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42));
    brightText = cleanRescueBinary(imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48));
    invertedImage = imcomplement(sharpened);

    variants = {grayImage, enhanced, sharpened, darkText, brightText, invertedImage, upscaled2, upscaled3};
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

    textValue = bestCandidate;
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
