%% OCR-First Car Plate Extractor
% Classical approach:
% 1. preprocess image to enhance plate text
% 2. use OCR to propose text regions
% 3. score only plate-like OCR results

clear;
clc;
close all;

imagePath = 'C:\APU\Matlab\Assignment\DataSet\images\IMG_4372.jpeg';
img = loadVehicleImage(imagePath);

[plateText, plateBox, plateCrop, ocrInput, candidateBoxes] = extractCarPlateOCRFirst(img);

figure('Name', 'Detected Plate');
imshow(img);
hold on;

if ~isempty(plateBox)
    rectangle('Position', plateBox, 'EdgeColor', 'g', 'LineWidth', 2);
    if strlength(plateText) > 0
        text(plateBox(1), max(plateBox(2) - 10, 10), char(plateText), ...
            'Color', 'yellow', 'FontSize', 13, 'FontWeight', 'bold', ...
            'BackgroundColor', 'black', 'Margin', 2);
        title(['Detected Plate: ' char(plateText)]);
    else
        title('Detected Plate Candidate');
    end
else
    title('No reliable plate candidate found');
    for n = 1:size(candidateBoxes, 1)
        rectangle('Position', candidateBoxes(n, :), 'EdgeColor', 'y', 'LineWidth', 1);
    end
end

hold off;

if ~isempty(plateCrop)
    figure('Name', 'Plate Crop');
    imshow(plateCrop);
    title('Best Plate Candidate');
end

if ~isempty(ocrInput)
    figure('Name', 'OCR Input');
    imshow(ocrInput);
    title('OCR Input');
end

disp('==== Detected Plate Text ====');
disp(plateText);

function [plateText, bestBox, bestCrop, bestOCRInput, candidateBoxes] = extractCarPlateOCRFirst(imageData)
    grayImage = preprocessVehicleImage(imageData);
    [rows, cols] = size(grayImage);

    % Focus on where front/rear plates usually appear, but keep enough
    % freedom for angled views.
    roi = [round(cols * 0.08), round(rows * 0.18), ...
        round(cols * 0.84), round(rows * 0.74)];

    searchImage = imcrop(grayImage, roi);

    % Build multiple OCR-friendly views because Malaysian plates vary a lot.
    brightPlateView = imtophat(searchImage, strel('disk', 15));
    darkPlateView = imbothat(searchImage, strel('disk', 15));
    contrastView = adapthisteq(searchImage, 'NumTiles', [8 8], 'ClipLimit', 0.02);

    ocrViews = {
        contrastView
        brightPlateView
        darkPlateView
    };

    plateText = "";
    bestBox = [];
    bestCrop = [];
    bestOCRInput = [];
    candidateBoxes = [];
    bestScore = -inf;

    % First pass: find plate-like rectangles using classical morphology,
    % then let OCR read only those candidate regions.
    shapeCandidates = generatePlateShapeCandidates(grayImage, roi);
    for i = 1:size(shapeCandidates, 1)
        expandedBox = shapeCandidates(i, :);
        if isBoxTooLarge(expandedBox, rows, cols)
            continue;
        end

        candidateBoxes = [candidateBoxes; expandedBox];
        plateCrop = imcrop(grayImage, expandedBox);
        if isempty(plateCrop)
            continue;
        end

        [textRegion, ocrInput] = preparePlateOCRInput(plateCrop);
        [recognizedText, confidence] = readPlateText(textRegion, ocrInput);
        score = scorePlateCandidate(recognizedText, confidence, expandedBox, rows, cols, "");
        score = score + 18; % Prefer true plate-body candidates over raw OCR words.

        if score > bestScore && score > 20
            bestScore = score;
            bestBox = expandedBox;
            bestCrop = textRegion;
            bestOCRInput = ocrInput;
            plateText = recognizedText;
        end
    end

    for v = 1:numel(ocrViews)
        currentView = ocrViews{v};
        currentView = im2uint8(currentView);

        try
            ocrResult = ocr(currentView);
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

            expandedBox = expandBoundingBox(absBox, rows, cols, 0.35, 0.20);
            if isBoxTooLarge(expandedBox, rows, cols)
                continue;
            end
            candidateBoxes = [candidateBoxes; expandedBox];

            plateCrop = imcrop(grayImage, expandedBox);
            if isempty(plateCrop)
                continue;
            end

            [textRegion, ocrInput] = preparePlateOCRInput(plateCrop);
            [recognizedText, confidence] = readPlateText(textRegion, ocrInput);
            score = scorePlateCandidate(recognizedText, confidence, expandedBox, rows, cols, word);

            if score > bestScore && score > 25
                bestScore = score;
                bestBox = expandedBox;
                bestCrop = textRegion;
                bestOCRInput = ocrInput;
                plateText = recognizedText;
            end
        end
    end

    % Fallback: if OCR words are weak, use MSER-like text-region search
    % via helperDetectTextRegions if available.
    if isempty(bestBox) || strlength(plateText) == 0
        [fallbackText, fallbackBox, fallbackCrop, fallbackInput, fallbackCandidates] = ...
            fallbackPlateSearch(grayImage);

        candidateBoxes = [candidateBoxes; fallbackCandidates];

        if ~isempty(fallbackBox)
            bestBox = fallbackBox;
            bestCrop = fallbackCrop;
            bestOCRInput = fallbackInput;
            plateText = fallbackText;
        end
    end
end

function preprocessedImage = preprocessVehicleImage(imageData)
    if ndims(imageData) == 3
        grayImage = rgb2gray(imageData);
    else
        grayImage = imageData;
    end

    grayImage = im2uint8(grayImage);
    grayImage = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.015);
    preprocessedImage = medfilt2(grayImage, [3 3]);
end

function [textRegion, ocrInput] = preparePlateOCRInput(plateCrop)
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

    textRegion = trimPlateBorders(enhanced);

    % Produce a cleaner OCR image for both dark-text and bright-text cases.
    darkText = imbinarize(textRegion, 'adaptive', ...
        'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    brightText = imbinarize(textRegion, 'adaptive', ...
        'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);

    darkText = cleanBinaryPlate(darkText);
    brightText = cleanBinaryPlate(brightText);

    if countCharacterLikeComponents(brightText) > countCharacterLikeComponents(darkText)
        ocrInput = brightText;
    else
        ocrInput = darkText;
    end

    [textRegion, ocrInput] = focusOnMainTextBand(textRegion, ocrInput);
end

function trimmed = trimPlateBorders(plateImage)
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

function [focusedRegion, focusedBinary] = focusOnMainTextBand(textRegion, binaryInput)
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

function [recognizedText, confidence] = readPlateText(textRegion, ocrInput)
    candidates = strings(0);
    scores = [];

    try
        result1 = ocr(im2uint8(textRegion));
        txt1 = formatPlateText(cleanPlateText(result1.Text));
        candidates(end + 1) = txt1; %#ok<AGROW>
        scores(end + 1) = plateTextScore(txt1, meanConfidence(result1)); %#ok<AGROW>
    catch
    end

    try
        result2 = ocr(im2uint8(ocrInput));
        txt2 = formatPlateText(cleanPlateText(result2.Text));
        candidates(end + 1) = txt2; %#ok<AGROW>
        scores(end + 1) = plateTextScore(txt2, meanConfidence(result2)); %#ok<AGROW>
    catch
    end

    try
        [lineText, lineScore] = readPlateByLines(textRegion, ocrInput);
        candidates(end + 1) = lineText; %#ok<AGROW>
        scores(end + 1) = lineScore; %#ok<AGROW>
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

function [recognizedText, score] = readPlateByLines(textRegion, ocrInput)
    recognizedText = "";
    score = -inf;

    variants = {im2uint8(textRegion), im2uint8(ocrInput) * 255};
    for i = 1:numel(variants)
        current = variants{i};
        [rows, ~] = size(current);

        whole = ocr(current);
        wholeText = formatPlateText(cleanPlateText(whole.Text));
        wholeScore = plateTextScore(wholeText, meanConfidence(whole));

        topHalf = current(1:max(1, round(rows * 0.55)), :);
        bottomHalf = current(max(1, round(rows * 0.35)):end, :);

        topResult = ocr(topHalf);
        bottomResult = ocr(bottomHalf);
        combinedText = formatPlateText(cleanPlateText(topResult.Text) + " " + cleanPlateText(bottomResult.Text));
        combinedScore = plateTextScore(combinedText, ...
            mean([meanConfidence(topResult), meanConfidence(bottomResult)], 'omitnan'));

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

function score = scorePlateCandidate(recognizedText, confidence, bbox, rows, cols, rawWord)
    aspectRatio = bbox(3) / bbox(4);
    centerX = (bbox(1) + bbox(3) / 2) / cols;
    centerY = (bbox(2) + bbox(4) / 2) / rows;
    relativeArea = (bbox(3) * bbox(4)) / (rows * cols);
    rawWordClean = cleanPlateText(rawWord);

    score = plateTextScore(recognizedText, confidence);
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
    end

    % Reject tiny side text such as EV/MAL stickers and labels.
    if strlength(rawWordClean) > 0 && strlength(rawWordClean) <= 3
        score = score - 20;
    end

    if strlength(rawWordClean) > 0 && ~containsDigitOrLikelyPlate(recognizedText) && ~containsDigitOrLikelyPlate(rawWordClean)
        score = score - 25;
    end
end

function [fallbackText, fallbackBox, fallbackCrop, fallbackInput, fallbackCandidates] = fallbackPlateSearch(grayImage)
    fallbackText = "";
    fallbackBox = [];
    fallbackCrop = [];
    fallbackInput = [];
    fallbackCandidates = zeros(0, 4);

    if exist('helperDetectTextRegions', 'file') ~= 2
        return;
    end

    params.MinArea = 50;
    params.MinAspectRatio = 0.1;
    params.MaxAspectRatio = 8;

    try
        bboxes = helperDetectTextRegions(grayImage, params);
    catch
        return;
    end

    if isempty(bboxes)
        return;
    end

    [rows, cols] = size(grayImage);
    bestScore = -inf;

    for i = 1:size(bboxes, 1)
        bbox = expandBoundingBox(bboxes(i, :), rows, cols, 0.20, 0.15);
        if isBoxTooLarge(bbox, rows, cols)
            continue;
        end
        fallbackCandidates(end + 1, :) = bbox; %#ok<AGROW>

        crop = imcrop(grayImage, bbox);
        [textRegion, ocrInput] = preparePlateOCRInput(crop);
        [recognizedText, confidence] = readPlateText(textRegion, ocrInput);
        score = scorePlateCandidate(recognizedText, confidence, bbox, rows, cols, "");

        if score > bestScore && score > 25
            bestScore = score;
            fallbackText = recognizedText;
            fallbackBox = bbox;
            fallbackCrop = textRegion;
            fallbackInput = ocrInput;
        end
    end
end

function score = plateTextScore(textValue, confidence)
    textValue = string(textValue);
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

    if ~isempty(regexp(char(textValue), '^[A-Z]{1,3}\s?\d{1,4}[A-Z]?$|^[A-Z]{1,3}\s?\d{1,4}$', 'once'))
        score = score + 35;
    end

    if all(isstrprop(char(textValue), 'alpha')) && strlength(textValue) > 0
        score = score - 30;
    end
end

function formattedText = formatPlateText(rawText)
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
        formattedText = prefix + " " + suffix;
    end
end

function confidence = meanConfidence(ocrResult)
    if isempty(ocrResult.CharacterConfidences)
        confidence = NaN;
    else
        confidence = mean(ocrResult.CharacterConfidences);
    end
end

function binaryPlate = cleanBinaryPlate(binaryPlate)
    binaryPlate = imclearborder(binaryPlate);
    binaryPlate = bwareaopen(binaryPlate, 20);
    binaryPlate = imclose(binaryPlate, strel('rectangle', [3 3]));
    binaryPlate = imopen(binaryPlate, strel('rectangle', [2 2]));
end

function charCount = countCharacterLikeComponents(binaryImage)
    cc = bwconncomp(binaryImage);
    stats = regionprops(cc, 'BoundingBox', 'Area');
    charCount = 0;

    for j = 1:numel(stats)
        box = stats(j).BoundingBox;
        aspectRatio = box(3) / box(4);
        area = stats(j).Area;

        if area > 20 && area < 4000 && aspectRatio > 0.08 && aspectRatio < 1.5
            charCount = charCount + 1;
        end
    end
end

function expandedBox = expandBoundingBox(bbox, rows, cols, yPadRatio, xPadRatio)
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

function cleanedText = cleanPlateText(rawText)
    cleanedText = upper(string(rawText));
    cleanedText = regexprep(cleanedText, '[^A-Z0-9]', '');
end

function tf = isBoxTooLarge(bbox, rows, cols)
    relativeArea = (bbox(3) * bbox(4)) / (rows * cols);
    tf = bbox(3) > cols * 0.55 || bbox(4) > rows * 0.28 || relativeArea > 0.22;
end

function candidates = generatePlateShapeCandidates(grayImage, roi)
    [rows, cols] = size(grayImage);
    searchImage = imcrop(grayImage, roi);
    searchRows = size(searchImage, 1);
    searchCols = size(searchImage, 2);

    edgeMask = edge(searchImage, 'Canny');
    edgeMask = imclose(edgeMask, strel('rectangle', [4 18]));
    edgeMask = imfill(edgeMask, 'holes');
    edgeMask = bwareaopen(edgeMask, 120);

    darkMask = searchImage < 110;
    darkMask = imclose(darkMask, strel('rectangle', [5 21]));
    darkMask = imfill(darkMask, 'holes');
    darkMask = bwareaopen(darkMask, 150);

    brightMask = searchImage > 150;
    brightMask = imclose(brightMask, strel('rectangle', [5 21]));
    brightMask = imfill(brightMask, 'holes');
    brightMask = bwareaopen(brightMask, 150);

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
            absBox = expandBoundingBox(absBox, rows, cols, 0.18, 0.12);
            candidates(end + 1, :) = absBox; %#ok<AGROW>
        end
    end

    if ~isempty(candidates)
        candidates = unique(round(candidates), 'rows');
    end
end

function tf = containsDigitOrLikelyPlate(textValue)
    textValue = cleanPlateText(textValue);
    tf = any(isstrprop(char(textValue), 'digit')) || ...
        ~isempty(regexp(char(textValue), '^[A-Z]{1,3}\d{1,4}[A-Z]?$', 'once'));
end

function imageData = loadVehicleImage(imagePath)
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
        % Keep original image if EXIF orientation is unavailable.
    end
end
