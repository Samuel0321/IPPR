function result = extractCarPlateFromImage_v3(inputValue)
%EXTRACTCARPLATEFROMIMAGE_V3 OCR-first fallback extractor.
% This version leans more on OCR-driven candidate proposal and keeps the
% crop that produces the strongest plate-like text score.

    if ischar(inputValue) || isstring(inputValue)
        imageData = loadVehicleImageV3(char(inputValue));
    else
        imageData = inputValue;
    end

    [plateText, plateBox, plateImage, binaryPlate, candidateBoxes, debugReport] = extractCarPlateOCRFirstV3(imageData);

    result = struct( ...
        'Image', imageData, ...
        'PlateText', string(plateText), ...
        'PlateBox', plateBox, ...
        'PlateImage', plateImage, ...
        'BinaryPlate', binaryPlate, ...
        'CandidateBoxes', candidateBoxes, ...
        'DebugReport', debugReport);
end

function [plateText, bestBox, bestCrop, bestOCRInput, candidateBoxes, debugReport] = extractCarPlateOCRFirstV3(imageData)
    grayImage = preprocessVehicleImageV3(imageData);
    [rows, cols] = size(grayImage);
    debugReport = initDebugReportV3(imageData);
    debugReport = addDebugStepV3(debugReport, 'Step 1 - Preprocessed grayscale', grayImage, ...
        'Converted to grayscale, enhanced contrast, then median filtered.');

    roi = [round(cols * 0.08), round(rows * 0.18), ...
        round(cols * 0.84), round(rows * 0.74)];

    searchImage = imcrop(grayImage, roi);
    debugReport = addDebugStepV3(debugReport, 'Step 2 - Search ROI', searchImage, ...
        'Main OCR-first search area used by v3.');

    brightPlateView = imtophat(searchImage, strel('disk', 15));
    darkPlateView = imbothat(searchImage, strel('disk', 15));
    contrastView = adapthisteq(searchImage, 'NumTiles', [8 8], 'ClipLimit', 0.02);
    debugReport = addDebugStepV3(debugReport, 'Step 3 - Contrast view', contrastView, ...
        'CLAHE-enhanced ROI for OCR proposal.');
    debugReport = addDebugStepV3(debugReport, 'Step 4 - Bright plate view', brightPlateView, ...
        'Tophat view to emphasize bright plate regions.');
    debugReport = addDebugStepV3(debugReport, 'Step 5 - Dark plate view', darkPlateView, ...
        'Blackhat view to emphasize dark text and shadows.');

    ocrViews = {
        contrastView
        brightPlateView
        darkPlateView
    };

    plateText = "";
    bestBox = [];
    bestCrop = [];
    bestOCRInput = [];
    candidateBoxes = zeros(0, 4);
    bestScore = -inf;

    [shapeCandidates, shapeDebug] = generatePlateShapeCandidatesV3(grayImage, roi);
    debugReport = appendDebugStepsV3(debugReport, shapeDebug);
    for i = 1:size(shapeCandidates, 1)
        expandedBox = shapeCandidates(i, :);
        if isBoxTooLargeV3(expandedBox, rows, cols)
            continue;
        end

        candidateBoxes(end + 1, :) = expandedBox; %#ok<AGROW>
        plateCrop = imcrop(grayImage, expandedBox);
        if isempty(plateCrop)
            continue;
        end

        [textRegion, ocrInput] = preparePlateOCRInputV3(plateCrop);
        [recognizedText, confidence] = readPlateTextV3(textRegion, ocrInput);
        score = scorePlateCandidateV3(recognizedText, confidence, expandedBox, rows, cols, "");
        score = score + 18;

        if score > bestScore && score > 20
            bestScore = score;
            bestBox = expandedBox;
            bestCrop = textRegion;
            bestOCRInput = ocrInput;
            plateText = recognizedText;
        end
    end

    for v = 1:numel(ocrViews)
        currentView = im2uint8(ocrViews{v});

        try
            ocrResult = runOCRWithFallbackV3(currentView);
        catch
            continue;
        end

        if isempty(ocrResult.Words)
            continue;
        end

        for k = 1:numel(ocrResult.Words)
            word = string(ocrResult.Words{k});
            bbox = ocrResult.WordBoundingBoxes(k, :);
            absBox = [bbox(1) + roi(1), bbox(2) + roi(2), bbox(3), bbox(4)];

            expandedBox = expandBoundingBoxV3(absBox, rows, cols, 0.35, 0.20);
            if isBoxTooLargeV3(expandedBox, rows, cols)
                continue;
            end
            candidateBoxes(end + 1, :) = expandedBox; %#ok<AGROW>

            plateCrop = imcrop(grayImage, expandedBox);
            if isempty(plateCrop)
                continue;
            end

            [textRegion, ocrInput] = preparePlateOCRInputV3(plateCrop);
            [recognizedText, confidence] = readPlateTextV3(textRegion, ocrInput);
            score = scorePlateCandidateV3(recognizedText, confidence, expandedBox, rows, cols, word);

            if score > bestScore && score > 25
                bestScore = score;
                bestBox = expandedBox;
                bestCrop = textRegion;
                bestOCRInput = ocrInput;
                plateText = recognizedText;
            end
        end
    end

    if ~isempty(candidateBoxes)
        candidateBoxes = unique(round(candidateBoxes), 'rows');
    end

    debugReport = addDebugStepV3(debugReport, 'Step 9 - Candidate boxes', ...
        overlayBoxesOnImageV3(imageData, candidateBoxes), ...
        sprintf('Total unique candidate boxes explored in v3: %d', size(candidateBoxes, 1)));

    if ~isempty(bestCrop)
        debugReport = addDebugStepV3(debugReport, 'Step 10 - Best text region', bestCrop, ...
            sprintf('Best v3 OCR text: "%s".', char(string(plateText))));
    end
    if ~isempty(bestOCRInput)
        debugReport = addDebugStepV3(debugReport, 'Step 11 - OCR input', bestOCRInput, ...
            sprintf('Best v3 score: %.2f', bestScore));
    end

    if ~isAcceptableFinalPlateTextV3(plateText, bestBox, rows, cols)
        plateText = "";
        debugReport.Status = "failed";
        if isempty(candidateBoxes)
            debugReport.Notes = "v3 did not produce any valid candidate boxes.";
        else
            debugReport.Notes = sprintf('v3 explored %d candidates, but none produced reliable OCR text.', size(candidateBoxes, 1));
        end
    else
        debugReport.Status = "completed";
        debugReport.Notes = sprintf('v3 selected a candidate with score %.2f and text "%s".', ...
            bestScore, char(string(plateText)));
    end
end

function preprocessedImage = preprocessVehicleImageV3(imageData)
    if ndims(imageData) == 3
        grayImage = rgb2gray(imageData);
    else
        grayImage = imageData;
    end

    grayImage = im2uint8(grayImage);
    grayImage = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.015);
    preprocessedImage = medfilt2(grayImage, [3 3]);
end

function [textRegion, ocrInput] = preparePlateOCRInputV3(plateCrop)
    plateCrop = imresize(plateCrop, 2);
    plateCrop = im2uint8(plateCrop);

    reflectionMask = plateCrop > 235;
    filtered = medfilt2(plateCrop, [3 3]);
    plateCrop(reflectionMask) = filtered(reflectionMask);

    [cropRows, cropCols] = size(plateCrop);
    tileRows = max(2, min(8, floor(cropRows / 16)));
    tileCols = max(2, min(8, floor(cropCols / 16)));
    enhanced = adapthisteq(plateCrop, 'NumTiles', [tileRows tileCols], 'ClipLimit', 0.02);
    enhanced = imsharpen(enhanced, 'Radius', 1.0, 'Amount', 1.0);

    textRegion = trimPlateBordersV3(enhanced);

    darkText = imbinarize(textRegion, 'adaptive', ...
        'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    brightText = imbinarize(textRegion, 'adaptive', ...
        'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);

    darkText = cleanBinaryPlateV3(darkText);
    brightText = cleanBinaryPlateV3(brightText);

    if countCharacterLikeComponentsV3(brightText) > countCharacterLikeComponentsV3(darkText)
        ocrInput = brightText;
    else
        ocrInput = darkText;
    end

    [textRegion, ocrInput] = focusOnMainTextBandV3(textRegion, ocrInput);
end

function trimmed = trimPlateBordersV3(plateImage)
    [rows, cols] = size(plateImage);
    trimmed = plateImage;

    edgeMask = edge(plateImage, 'Canny');
    edgeMask = imclose(edgeMask, strel('rectangle', [3 9]));
    edgeMask = bwareaopen(edgeMask, 40);
    stats = regionprops(edgeMask, 'BoundingBox', 'Area', 'Centroid');

    bestScore = -inf;
    bestBox = [];

    for i = 1:numel(stats)
        bbox = stats(i).BoundingBox;
        aspectRatio = bbox(3) / bbox(4);
        centerY = stats(i).Centroid(2) / rows;

        if bbox(3) < cols * 0.20 || bbox(4) < rows * 0.18
            continue;
        end

        if aspectRatio < 1.0 || aspectRatio > 8.0
            continue;
        end

        score = stats(i).Area - abs(centerY - 0.5) * 200;
        if score > bestScore
            bestScore = score;
            bestBox = bbox;
        end
    end

    if ~isempty(bestBox)
        x1 = max(1, floor(bestBox(1) - cols * 0.04));
        y1 = max(1, floor(bestBox(2) - rows * 0.08));
        x2 = min(cols, ceil(bestBox(1) + bestBox(3) + cols * 0.04));
        y2 = min(rows, ceil(bestBox(2) + bestBox(4) + rows * 0.08));
        trimmed = plateImage(y1:y2, x1:x2);
    else
        y1 = max(1, round(rows * 0.15));
        y2 = min(rows, round(rows * 0.85));
        x1 = max(1, round(cols * 0.08));
        x2 = min(cols, round(cols * 0.92));
        trimmed = plateImage(y1:y2, x1:x2);
    end
end

function [focusedRegion, focusedBinary] = focusOnMainTextBandV3(textRegion, binaryInput)
    focusedRegion = textRegion;
    focusedBinary = binaryInput;

    if isempty(binaryInput) || nnz(binaryInput) == 0
        return;
    end

    [rows, cols] = size(binaryInput);
    rowProfile = sum(binaryInput, 2);
    if max(rowProfile) == 0
        return;
    end

    rowMask = rowProfile > max(rowProfile) * 0.35;
    rowMask = imclose(rowMask, ones(9, 1));

    rowStarts = find(diff([0; rowMask]) == 1);
    rowEnds = find(diff([rowMask; 0]) == -1);

    bestScore = -inf;
    bestRows = [];

    for i = 1:numel(rowStarts)
        y1 = rowStarts(i);
        y2 = rowEnds(i);
        bandHeight = y2 - y1 + 1;
        bandSum = sum(rowProfile(y1:y2));
        centerY = ((y1 + y2) / 2) / rows;

        if bandHeight < rows * 0.12
            continue;
        end

        score = bandSum + bandHeight * 20 - abs(centerY - 0.55) * 120;
        if score > bestScore
            bestScore = score;
            bestRows = [y1 y2];
        end
    end

    if isempty(bestRows)
        return;
    end

    bandBinary = binaryInput(bestRows(1):bestRows(2), :);
    colProfile = sum(bandBinary, 1);

    if max(colProfile) == 0
        return;
    end

    colMask = colProfile > max(colProfile) * 0.18;
    colMask = imclose(colMask, ones(1, 9));

    colStarts = find(diff([0 colMask]) == 1);
    colEnds = find(diff([colMask 0]) == -1);

    if isempty(colStarts)
        x1 = 1;
        x2 = cols;
    else
        widths = colEnds - colStarts + 1;
        [~, idx] = max(widths);
        x1 = max(1, colStarts(idx) - round(cols * 0.03));
        x2 = min(cols, colEnds(idx) + round(cols * 0.03));
    end

    y1 = max(1, bestRows(1) - round(rows * 0.05));
    y2 = min(rows, bestRows(2) + round(rows * 0.05));

    focusedRegion = textRegion(y1:y2, x1:x2);
    focusedBinary = binaryInput(y1:y2, x1:x2);
end

function [recognizedText, confidence] = readPlateTextV3(textRegion, ocrInput)
    candidates = strings(0, 1);
    scores = [];

    try
        result1 = runOCRWithFallbackV3(im2uint8(textRegion));
        txt1 = formatPlateTextV3(cleanPlateTextV3(result1.Text));
        candidates(end + 1, 1) = txt1;
        scores(end + 1) = plateTextScoreV3(txt1, meanConfidenceV3(result1));
    catch
    end

    try
        result2 = runOCRWithFallbackV3(im2uint8(ocrInput));
        txt2 = formatPlateTextV3(cleanPlateTextV3(result2.Text));
        candidates(end + 1, 1) = txt2;
        scores(end + 1) = plateTextScoreV3(txt2, meanConfidenceV3(result2));
    catch
    end

    try
        [lineText, lineScore] = readPlateByLinesV3(textRegion, ocrInput);
        candidates(end + 1, 1) = lineText;
        scores(end + 1) = lineScore;
    catch
    end

    if isempty(scores)
        recognizedText = "";
        confidence = NaN;
        return;
    end

    [bestScore, idx] = max(scores);
    recognizedText = candidates(idx);
    confidence = bestScore;
end

function [recognizedText, score] = readPlateByLinesV3(textRegion, ocrInput)
    recognizedText = "";
    score = -inf;

    variants = {im2uint8(textRegion), im2uint8(ocrInput) * 255};
    for i = 1:numel(variants)
        current = variants{i};
        rows = size(current, 1);

        whole = runOCRWithFallbackV3(current);
        wholeText = formatPlateTextV3(cleanPlateTextV3(whole.Text));
        wholeScore = plateTextScoreV3(wholeText, meanConfidenceV3(whole));

        topHalf = current(1:max(1, round(rows * 0.55)), :);
        bottomHalf = current(max(1, round(rows * 0.35)):end, :);

        topResult = runOCRWithFallbackV3(topHalf);
        bottomResult = runOCRWithFallbackV3(bottomHalf);
        combinedText = formatPlateTextV3(cleanPlateTextV3(topResult.Text) + cleanPlateTextV3(bottomResult.Text));
        combinedScore = plateTextScoreV3(combinedText, ...
            mean([meanConfidenceV3(topResult), meanConfidenceV3(bottomResult)], 'omitnan'));

        if combinedScore > wholeScore
            currentText = combinedText;
            currentScore = combinedScore;
        else
            currentText = wholeText;
            currentScore = wholeScore;
        end

        if currentScore > score
            score = currentScore;
            recognizedText = currentText;
        end
    end
end

function score = scorePlateCandidateV3(recognizedText, confidence, bbox, rows, cols, rawWord)
    aspectRatio = bbox(3) / bbox(4);
    centerX = (bbox(1) + bbox(3) / 2) / cols;
    centerY = (bbox(2) + bbox(4) / 2) / rows;
    relativeArea = (bbox(3) * bbox(4)) / (rows * cols);
    rawWordClean = cleanPlateTextV3(rawWord);

    score = plateTextScoreV3(recognizedText, confidence);
    score = score + strlength(rawWordClean) * 2;

    if aspectRatio >= 1.6 && aspectRatio <= 8.5
        score = score + 15;
    end
    if centerY >= 0.35 && centerY <= 0.88
        score = score + 12;
    else
        score = score - 20;
    end
    if centerX >= 0.10 && centerX <= 0.90
        score = score + 8;
    end
    if bbox(3) > cols * 0.45 || bbox(4) > rows * 0.22
        score = score - 25;
    end
    if relativeArea > 0.20
        score = score - 80;
    elseif relativeArea > 0.10
        score = score - 35;
    end
    if strlength(recognizedText) == 0
        score = score - 60;
    elseif strlength(recognizedText) <= 3 && ~isStrictShortPlateTextV3(recognizedText)
        score = score - 70;
    end
    if strlength(rawWordClean) > 0 && strlength(rawWordClean) <= 3
        score = score - 20;
    end
    if strlength(rawWordClean) > 0 && ...
            ~containsDigitOrLikelyPlateV3(recognizedText) && ~containsDigitOrLikelyPlateV3(rawWordClean)
        score = score - 25;
    end
end

function score = plateTextScoreV3(textValue, confidence)
    textValue = cleanPlateTextV3(textValue);
    score = strlength(textValue) * 10;

    if ~isnan(confidence)
        score = score + confidence / 4;
    end
    if strlength(textValue) >= 3 && strlength(textValue) <= 10
        score = score + 20;
    end
    if any(isstrprop(char(textValue), 'alpha')) && any(isstrprop(char(textValue), 'digit'))
        score = score + 20;
    end
    if strlength(textValue) >= 4 && ...
            ~isempty(regexp(char(textValue), '^[A-Z]{1,3}\d{1,4}[A-Z]?$|^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$', 'once'))
        score = score + 35;
    elseif isStrictShortPlateTextV3(textValue)
        score = score + 10;
    end
    if all(isstrprop(char(textValue), 'alpha')) && strlength(textValue) > 0
        score = score - 30;
    end
end

function formattedText = formatPlateTextV3(rawText)
    rawText = upper(string(rawText));
    rawText = regexprep(rawText, '\s+', '');
    rawText = regexprep(rawText, '[^A-Z0-9]', '');
    formattedText = rawText;

    if strlength(rawText) < 2
        return;
    end

    firstDigitIndex = regexp(char(rawText), '\d', 'once');
    if isempty(firstDigitIndex) || firstDigitIndex <= 1
        return;
    end

    prefix = extractBetween(rawText, 1, firstDigitIndex - 1);
    suffix = extractAfter(rawText, firstDigitIndex - 1);

    if strlength(prefix) >= 1 && strlength(prefix) <= 3 && ...
            strlength(suffix) >= 1 && strlength(suffix) <= 5
        formattedText = prefix + suffix;
    end
end

function confidence = meanConfidenceV3(ocrResult)
    if isempty(ocrResult.CharacterConfidences)
        confidence = NaN;
    else
        confidence = mean(ocrResult.CharacterConfidences, 'omitnan');
    end
end

function binaryPlate = cleanBinaryPlateV3(binaryPlate)
    binaryPlate = imclearborder(binaryPlate);
    binaryPlate = bwareaopen(binaryPlate, 20);
    binaryPlate = imclose(binaryPlate, strel('rectangle', [3 3]));
    binaryPlate = imopen(binaryPlate, strel('rectangle', [2 2]));
end

function charCount = countCharacterLikeComponentsV3(binaryImage)
    cc = bwconncomp(binaryImage);
    stats = regionprops(cc, 'BoundingBox', 'Area');
    charCount = 0;

    for i = 1:numel(stats)
        box = stats(i).BoundingBox;
        aspectRatio = box(3) / box(4);
        area = stats(i).Area;

        if area > 20 && area < 4000 && aspectRatio > 0.08 && aspectRatio < 1.5
            charCount = charCount + 1;
        end
    end
end

function expandedBox = expandBoundingBoxV3(bbox, rows, cols, yPadRatio, xPadRatio)
    x = bbox(1);
    y = bbox(2);
    w = bbox(3);
    h = bbox(4);

    xPad = w * xPadRatio;
    yPad = h * yPadRatio;

    x1 = max(1, floor(x - xPad));
    y1 = max(1, floor(y - yPad));
    x2 = min(cols, ceil(x + w + xPad));
    y2 = min(rows, ceil(y + h + yPad));

    expandedBox = [x1, y1, x2 - x1, y2 - y1];
end

function cleanedText = cleanPlateTextV3(rawText)
    cleanedText = upper(string(rawText));
    cleanedText = regexprep(cleanedText, '[^A-Z0-9]', '');
end

function result = runOCRWithFallbackV3(ocrInput)
    try
        result = ocr(ocrInput, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
        return;
    catch
    end

    try
        result = ocr(ocrInput);
        return;
    catch
    end

    result = [];
end

function tf = isUsablePlateTextV3(textValue)
    cleanedText = cleanPlateTextV3(textValue);
    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        tf = false;
        return;
    end

    hasAlpha = any(isstrprop(char(cleanedText), 'alpha'));
    hasDigit = any(isstrprop(char(cleanedText), 'digit'));
    tf = hasAlpha && hasDigit;
end

function tf = isAcceptableFinalPlateTextV3(textValue, bbox, rows, cols)
    textValue = cleanPlateTextV3(textValue);
    tf = false;
    if strlength(textValue) == 0 || isempty(bbox)
        return;
    end

    if strlength(textValue) >= 4 && ...
            ~isempty(regexp(char(textValue), '^[A-Z]{1,3}\d{1,4}[A-Z]?$|^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$', 'once'))
        tf = true;
        return;
    end

    if ~isStrictShortPlateTextV3(textValue)
        return;
    end

    aspectRatio = bbox(3) / max(bbox(4), 1);
    centerX = (bbox(1) + bbox(3) / 2) / cols;
    centerY = (bbox(2) + bbox(4) / 2) / rows;
    tf = aspectRatio >= 0.8 && aspectRatio <= 5.5 && ...
        centerX >= 0.28 && centerX <= 0.72 && centerY >= 0.28 && centerY <= 0.88;
end

function tf = isStrictShortPlateTextV3(textValue)
    textValue = cleanPlateTextV3(textValue);
    tf = ~isempty(regexp(char(textValue), '^[A-Z]\d{2,4}$', 'once'));
end

function tf = isBoxTooLargeV3(bbox, rows, cols)
    relativeArea = (bbox(3) * bbox(4)) / (rows * cols);
    tf = bbox(3) > cols * 0.55 || bbox(4) > rows * 0.28 || relativeArea > 0.22;
end

function [candidates, debugSteps] = generatePlateShapeCandidatesV3(grayImage, roi)
    [rows, cols] = size(grayImage);
    searchImage = imcrop(grayImage, roi);
    searchRows = size(searchImage, 1);
    searchCols = size(searchImage, 2);
    debugSteps = repmat(makeDebugStepV3("", [], ""), 0, 1);

    edgeMask = edge(searchImage, 'Canny');
    edgeMask = imclose(edgeMask, strel('rectangle', [4 18]));
    edgeMask = imfill(edgeMask, 'holes');
    edgeMask = bwareaopen(edgeMask, 120);
    debugSteps(end + 1, 1) = makeDebugStepV3('Step 6 - Shape edge mask', edgeMask, ...
        'Edge-driven plate-shape proposal mask.');

    darkMask = searchImage < 110;
    darkMask = imclose(darkMask, strel('rectangle', [5 21]));
    darkMask = imfill(darkMask, 'holes');
    darkMask = bwareaopen(darkMask, 150);
    debugSteps(end + 1, 1) = makeDebugStepV3('Step 7 - Shape dark mask', darkMask, ...
        'Dark-region proposal mask inside the v3 ROI.');

    brightMask = searchImage > 150;
    brightMask = imclose(brightMask, strel('rectangle', [5 21]));
    brightMask = imfill(brightMask, 'holes');
    brightMask = bwareaopen(brightMask, 150);
    debugSteps(end + 1, 1) = makeDebugStepV3('Step 8 - Shape bright mask', brightMask, ...
        'Bright-region proposal mask inside the v3 ROI.');

    masks = {edgeMask, darkMask, brightMask};
    candidates = zeros(0, 4);

    for m = 1:numel(masks)
        stats = regionprops(masks{m}, 'BoundingBox', 'Area', 'Extent', 'Solidity', 'Centroid');

        for i = 1:numel(stats)
            bbox = stats(i).BoundingBox;
            aspectRatio = bbox(3) / bbox(4);
            relativeArea = (bbox(3) * bbox(4)) / (searchRows * searchCols);
            centerX = stats(i).Centroid(1) / searchCols;
            centerY = stats(i).Centroid(2) / searchRows;

            if aspectRatio < 1.2 || aspectRatio > 8.5
                continue;
            end
            if relativeArea < 0.003 || relativeArea > 0.18
                continue;
            end
            if stats(i).Extent < 0.18 || stats(i).Solidity < 0.18
                continue;
            end
            if centerX < 0.10 || centerX > 0.90 || centerY < 0.18 || centerY > 0.92
                continue;
            end

            absBox = [bbox(1) + roi(1), bbox(2) + roi(2), bbox(3), bbox(4)];
            absBox = expandBoundingBoxV3(absBox, rows, cols, 0.18, 0.12);
            candidates(end + 1, :) = absBox; %#ok<AGROW>
        end
    end

    if ~isempty(candidates)
        candidates = unique(round(candidates), 'rows');
    end
end

function debugReport = initDebugReportV3(imageData)
    debugReport = struct( ...
        'Method', "v3", ...
        'Status', "running", ...
        'Notes', "", ...
        'Steps', repmat(makeDebugStepV3("", [], ""), 0, 1));
    debugReport = addDebugStepV3(debugReport, 'Input image', imageData, ...
        'Original image passed into v3 detector.');
end

function debugReport = addDebugStepV3(debugReport, titleText, imageData, descriptionText)
    debugReport.Steps(end + 1, 1) = makeDebugStepV3(titleText, imageData, descriptionText);
end

function debugReport = appendDebugStepsV3(debugReport, steps)
    if isempty(steps)
        return;
    end
    debugReport.Steps = [debugReport.Steps; steps];
end

function step = makeDebugStepV3(titleText, imageData, descriptionText)
    step = struct( ...
        'Title', string(titleText), ...
        'Image', imageData, ...
        'Description', string(descriptionText));
end

function overlayImage = overlayBoxesOnImageV3(imageData, candidateBoxes)
    if ndims(imageData) == 2
        overlayImage = repmat(im2uint8(imageData), 1, 1, 3);
    else
        overlayImage = im2uint8(imageData);
    end

    if isempty(candidateBoxes)
        return;
    end

    overlayImage = insertShape(overlayImage, 'Rectangle', candidateBoxes, ...
        'Color', 'yellow', 'LineWidth', 3);
end

function tf = containsDigitOrLikelyPlateV3(textValue)
    textValue = cleanPlateTextV3(textValue);
    tf = any(isstrprop(char(textValue), 'digit')) || ...
        (strlength(textValue) >= 4 && ~isempty(regexp(char(textValue), ...
        '^[A-Z]{1,3}\d{1,4}[A-Z]?$|^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$', 'once'))) || ...
        isStrictShortPlateTextV3(textValue);
end

function imageData = loadVehicleImageV3(imagePath)
    imageData = imread(imagePath);

    try
        imageInfo = imfinfo(imagePath);
        if isfield(imageInfo, 'Orientation')
            orientation = imageInfo.Orientation;

            if isnumeric(orientation)
                switch orientation
                    case 3
                        imageData = rot90(imageData, 2);
                    case 6
                        imageData = rot90(imageData, -1);
                    case 8
                        imageData = rot90(imageData, 1);
                end
            else
                orientationText = lower(string(orientation));

                if contains(orientationText, "180")
                    imageData = rot90(imageData, 2);
                elseif contains(orientationText, "90") && ...
                        (contains(orientationText, "clockwise") || contains(orientationText, "right"))
                    imageData = rot90(imageData, -1);
                elseif contains(orientationText, "90") && ...
                        (contains(orientationText, "counter") || contains(orientationText, "left"))
                    imageData = rot90(imageData, 1);
                end
            end
        end
    catch
    end
end
