function result = extractCarPlateFromImage(inputValue)
%EXTRACTCARPLATEFROMIMAGE Try multiple plate detectors in fallback order.
% The default order is v4, then v2, then v1, then v3. A result is accepted as soon
% as the OCR text looks plate-like for common Malaysian formats.

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
            '^[A-Z]{1,3}\d{1,4}[A-Z]?$|^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$', 'once'))
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
