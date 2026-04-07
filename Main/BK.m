%% Classical Car Plate Extractor
% Finds the most likely license plate region first, then runs OCR only on
% that candidate to avoid scanning road, sky, and other background areas.

clear;
clc;
close all;

imagePath = 'C:\APU\Matlab\Assignment\DataSet\images\2024-JPJ-ePlate-EV-Number-Plate-11.jpg';
img = loadVehicleImage(imagePath);

[plateText, plateBox, plateImage, binaryPlate, candidateBoxes] = extractCarPlate(img);

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

if ~isempty(plateImage)
    figure('Name', 'Plate Crop');
    imshow(plateImage);
    title('Best Plate Candidate');
end

if ~isempty(binaryPlate)
    figure('Name', 'OCR Input');
    imshow(binaryPlate);
    title('Binary Plate For OCR');
end

disp('==== Detected Plate Text ====');
disp(plateText);

if ~isempty(binaryPlate)
    imwrite(binaryPlate, 'C:\APU\Matlab\Assignment\DataSet\images\OCR_ready_plate.png');
end

function [plateText, bestBox, bestCrop, bestBinary, candidateBoxes] = extractCarPlate(imageData)
    grayImage = preprocessVehicleImage(imageData);
    [rows, cols] = size(grayImage);

    % Restrict the search to the central/lower part of the vehicle scene.
    % Rear plates are usually near the horizontal center and below mid-height.
    rowStart = max(1, round(rows * 0.35));
    rowEnd = min(rows, round(rows * 0.92));
    colStart = max(1, round(cols * 0.20));
    colEnd = min(cols, round(cols * 0.80));

    searchMask = false(rows, cols);
    searchMask(rowStart:rowEnd, colStart:colEnd) = true;

    edgeImage = edge(grayImage, 'Canny');
    edgeImage = edgeImage & searchMask;

    horizontalSE = strel('rectangle', [4 18]);
    candidateMask = imclose(edgeImage, horizontalSE);
    candidateMask = imfill(candidateMask, 'holes');
    candidateMask = bwareaopen(candidateMask, 150);

    stats = regionprops(candidateMask, 'BoundingBox', 'Area', ...
        'Extent', 'Solidity', 'Eccentricity', 'Centroid');

    % Fallback for dark license plates with bright text, common in night
    % scenes where edge-only detection can miss the plate body.
    darkMask = grayImage < 85;
    darkMask = darkMask & searchMask;
    darkMask = imclose(darkMask, strel('rectangle', [5 21]));
    darkMask = imopen(darkMask, strel('rectangle', [3 9]));
    darkMask = imfill(darkMask, 'holes');
    darkMask = bwareaopen(darkMask, 250);

    darkStats = regionprops(darkMask, 'BoundingBox', 'Area', ...
        'Extent', 'Solidity', 'Eccentricity', 'Centroid');
    stats = [stats; darkStats];

    % Additional path for bright rectangular plates with dark text.
    brightMask = grayImage > 150;
    brightMask = brightMask & searchMask;
    brightMask = imclose(brightMask, strel('rectangle', [5 17]));
    brightMask = imopen(brightMask, strel('rectangle', [3 7]));
    brightMask = imfill(brightMask, 'holes');
    brightMask = bwareaopen(brightMask, 250);

    brightStats = regionprops(brightMask, 'BoundingBox', 'Area', ...
        'Extent', 'Solidity', 'Eccentricity', 'Centroid');
    stats = [stats; brightStats];

    bestScore = -inf;
    bestBox = [];
    bestCrop = [];
    bestBinary = [];
    candidateBoxes = [];
    plateText = "";

    for i = 1:numel(stats)
        bbox = stats(i).BoundingBox;
        aspectRatio = bbox(3) / bbox(4);
        boxArea = bbox(3) * bbox(4);
        relativeArea = boxArea / (rows * cols);
        centerX = stats(i).Centroid(1) / cols;
        centerY = stats(i).Centroid(2) / rows;
        distanceFromCenter = abs(centerX - 0.5);

        % Plate-like geometry filters.
        if aspectRatio < 0.8 || aspectRatio > 8.5
            continue;
        end

        if relativeArea < 0.0015 || relativeArea > 0.20
            continue;
        end

        if stats(i).Extent < 0.20 || stats(i).Solidity < 0.20
            continue;
        end

        if centerY < 0.35 || centerY > 0.92
            continue;
        end

        if centerX < 0.12 || centerX > 0.88
            continue;
        end

        expandedBox = expandBoundingBox(bbox, rows, cols, 0.08, 0.18);
        refinedBox = refinePlateBox(grayImage, expandedBox);
        candidateBoxes = [candidateBoxes; refinedBox];
        plateCrop = imcrop(grayImage, refinedBox);
        [focusedPlate, textRegion, enhancedPlate, binaryPlate, charCount] = preparePlateForOCR(plateCrop);

        if charCount < 1 || charCount > 12
            continue;
        end

        [recognizedText, textConfidence] = runPlateOCR(focusedPlate, textRegion, enhancedPlate, binaryPlate);

        if strlength(recognizedText) == 0
            recognizedText = segmentPlateText(binaryPlate);
            textConfidence = NaN;
        end

        if strlength(recognizedText) == 0
            recognizedText = readPlateByLines(focusedPlate, textRegion, enhancedPlate, binaryPlate);
            textConfidence = NaN;
        end

        score = charCount * 8 + stats(i).Extent * 20 + stats(i).Solidity * 15;

        if ~isnan(textConfidence)
            score = score + textConfidence / 5;
        end

        if strlength(recognizedText) >= 2 && strlength(recognizedText) <= 12
            score = score + 20;
        end

        % Rear plate prior: reward candidates near image center and lower-middle.
        score = score - distanceFromCenter * 120;
        score = score - abs(centerY - 0.60) * 70;

        % Penalize top-side background text and oversized background regions.
        if refinedBox(2) < rows * 0.35
            score = score - 35;
        end

        if refinedBox(3) > cols * 0.35 || refinedBox(4) > rows * 0.18
            score = score - 40;
        end

        if strlength(recognizedText) == 0
            score = score - 15;
        end

        if score > bestScore
            bestScore = score;
            bestBox = refinedBox;
            bestCrop = textRegion;
            bestBinary = binaryPlate;
            plateText = recognizedText;
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

function [focusedPlate, textRegion, enhancedPlate, bestBinary, charCount] = preparePlateForOCR(plateCrop)
    plateCrop = imresize(plateCrop, 2);
    focusedPlate = refinePlateCrop(plateCrop);
    textRegion = extractTextRegion(focusedPlate);

    reflectionMask = textRegion > 230;
    reflectionReduced = medfilt2(textRegion, [3 3]);
    textRegion(reflectionMask) = reflectionReduced(reflectionMask);

    enhancedPlate = adapthisteq(textRegion, 'NumTiles', [8 8], 'ClipLimit', 0.02);
    enhancedPlate = medfilt2(enhancedPlate, [3 3]);
    enhancedPlate = imsharpen(enhancedPlate, 'Radius', 1.0, 'Amount', 1.2);

    darkText = imbinarize(enhancedPlate, 'adaptive', ...
        'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    brightText = imbinarize(enhancedPlate, 'adaptive', ...
        'ForegroundPolarity', 'bright', 'Sensitivity', 0.50);

    % Extra fallback for black plates with bright characters.
    invertedPlate = imcomplement(enhancedPlate);
    invertedBrightText = imbinarize(invertedPlate, 'adaptive', ...
        'ForegroundPolarity', 'dark', 'Sensitivity', 0.48);

    darkText = cleanBinaryPlate(darkText);
    brightText = cleanBinaryPlate(brightText);
    invertedBrightText = cleanBinaryPlate(invertedBrightText);

    darkCount = countCharacterLikeComponents(darkText);
    brightCount = countCharacterLikeComponents(brightText);
    invertedCount = countCharacterLikeComponents(invertedBrightText);

    if brightCount >= darkCount && brightCount >= invertedCount
        bestBinary = brightText;
        charCount = brightCount;
    elseif invertedCount >= darkCount
        bestBinary = invertedBrightText;
        charCount = invertedCount;
    else
        bestBinary = darkText;
        charCount = darkCount;
    end
end

function focusedPlate = refinePlateCrop(plateCrop)
    [rows, cols] = size(plateCrop);
    darkMask = plateCrop < 190;
    darkMask = imclose(darkMask, strel('rectangle', [5 9]));
    darkMask = imfill(darkMask, 'holes');
    darkMask = bwareaopen(darkMask, 150);

    stats = regionprops(darkMask, 'BoundingBox', 'Area', 'Centroid');
    focusedPlate = plateCrop;
    bestScore = -inf;
    bestBox = [];

    for i = 1:numel(stats)
        bbox = stats(i).BoundingBox;
        centerX = stats(i).Centroid(1) / cols;
        centerY = stats(i).Centroid(2) / rows;
        aspectRatio = bbox(3) / bbox(4);

        if aspectRatio < 0.8 || aspectRatio > 6.5
            continue;
        end

        score = stats(i).Area ...
            - abs(centerX - 0.5) * 500 ...
            - abs(centerY - 0.5) * 300;

        if score > bestScore
            bestScore = score;
            bestBox = bbox;
        end
    end

    if ~isempty(bestBox)
        focusedPlate = imcrop(plateCrop, expandBoundingBox(bestBox, rows, cols, 0.08, 0.08));
    end
end

function textRegion = extractTextRegion(focusedPlate)
    [rows, cols] = size(focusedPlate);
    textRegion = focusedPlate;

    darkChars = focusedPlate < 170;
    darkChars = bwareaopen(darkChars, 20);

    brightChars = focusedPlate > 150;
    brightChars = bwareaopen(brightChars, 20);

    masks = {darkChars, brightChars};
    bestScore = -inf;
    bestBox = [];

    for k = 1:numel(masks)
        currentMask = masks{k};
        currentMask = imclose(currentMask, strel('rectangle', [3 3]));
        stats = regionprops(currentMask, 'BoundingBox', 'Area', 'Centroid');

        for i = 1:numel(stats)
            bbox = stats(i).BoundingBox;
            aspectRatio = bbox(3) / bbox(4);
            centerY = stats(i).Centroid(2) / rows;

            if bbox(3) < cols * 0.08 || bbox(4) < rows * 0.18
                continue;
            end

            if aspectRatio < 0.15 || aspectRatio > 1.3
                continue;
            end

            score = stats(i).Area - abs(centerY - 0.5) * 150;

            if score > bestScore
                bestScore = score;
                bestBox = bbox;
            end
        end
    end

    if ~isempty(bestBox)
        x1 = max(1, floor(bestBox(1) - cols * 0.06));
        y1 = max(1, floor(bestBox(2) - rows * 0.10));
        x2 = min(cols, ceil(bestBox(1) + bestBox(3) + cols * 0.06));
        y2 = min(rows, ceil(bestBox(2) + bestBox(4) + rows * 0.10));
        textRegion = focusedPlate(y1:y2, x1:x2);
        return;
    end

    % Fallback: keep the central band and ignore thick plate borders/frame.
    y1 = max(1, round(rows * 0.18));
    y2 = min(rows, round(rows * 0.82));
    x1 = max(1, round(cols * 0.08));
    x2 = min(cols, round(cols * 0.92));
    textRegion = focusedPlate(y1:y2, x1:x2);
end

function refinedBox = refinePlateBox(grayImage, initialBox)
    [rows, cols] = size(grayImage);
    localCrop = imcrop(grayImage, initialBox);
    localCrop = im2uint8(localCrop);

    darkMask = localCrop < 200;
    darkMask = imclose(darkMask, strel('rectangle', [5 11]));
    darkMask = imfill(darkMask, 'holes');
    darkMask = bwareaopen(darkMask, 120);

    edgeMask = edge(localCrop, 'Canny');
    edgeMask = imclose(edgeMask, strel('rectangle', [3 15]));
    edgeMask = imfill(edgeMask, 'holes');
    edgeMask = bwareaopen(edgeMask, 120);

    combinedMask = darkMask | edgeMask;
    stats = regionprops(combinedMask, 'BoundingBox', 'Area', 'Extent', 'Solidity', 'Centroid');

    refinedBox = initialBox;
    bestScore = -inf;

    for i = 1:numel(stats)
        bbox = stats(i).BoundingBox;
        aspectRatio = bbox(3) / bbox(4);
        centerX = stats(i).Centroid(1) / size(localCrop, 2);
        centerY = stats(i).Centroid(2) / size(localCrop, 1);

        if aspectRatio < 1.0 || aspectRatio > 7.5
            continue;
        end

        score = stats(i).Area ...
            + stats(i).Extent * 150 ...
            + stats(i).Solidity * 100 ...
            - abs(centerX - 0.5) * 200 ...
            - abs(centerY - 0.55) * 160;

        if score > bestScore
            bestScore = score;
            x1 = max(1, floor(initialBox(1) + bbox(1) - 1));
            y1 = max(1, floor(initialBox(2) + bbox(2) - 1));
            x2 = min(cols, ceil(x1 + bbox(3)));
            y2 = min(rows, ceil(y1 + bbox(4)));
            refinedBox = expandBoundingBox([x1, y1, x2 - x1, y2 - y1], rows, cols, 0.10, 0.10);
        end
    end
end

function [recognizedText, textConfidence] = runPlateOCR(focusedPlate, textRegion, enhancedPlate, binaryPlate)
    ocrFocused = ocr(im2uint8(focusedPlate));
    textFocused = cleanPlateText(ocrFocused.Text);
    confFocused = meanConfidence(ocrFocused);

    ocrTextRegion = ocr(im2uint8(textRegion));
    textTextRegion = cleanPlateText(ocrTextRegion.Text);
    confTextRegion = meanConfidence(ocrTextRegion);

    ocrGray = ocr(im2uint8(enhancedPlate));
    textGray = cleanPlateText(ocrGray.Text);
    confGray = meanConfidence(ocrGray);

    ocrBinary = ocr(im2uint8(binaryPlate));
    textBinary = cleanPlateText(ocrBinary.Text);
    confBinary = meanConfidence(ocrBinary);

    scoreFocused = plateTextScore(textFocused, confFocused);
    scoreTextRegion = plateTextScore(textTextRegion, confTextRegion);
    scoreGray = plateTextScore(textGray, confGray);
    scoreBinary = plateTextScore(textBinary, confBinary);

    if scoreTextRegion >= scoreFocused && scoreTextRegion >= scoreGray && scoreTextRegion >= scoreBinary
        recognizedText = textTextRegion;
        textConfidence = confTextRegion;
    elseif scoreFocused >= scoreGray && scoreFocused >= scoreBinary
        recognizedText = textFocused;
        textConfidence = confFocused;
    elseif scoreGray >= scoreBinary
        recognizedText = textGray;
        textConfidence = confGray;
    else
        recognizedText = textBinary;
        textConfidence = confBinary;
    end

    recognizedText = formatPlateText(recognizedText);
end

function recognizedText = segmentPlateText(binaryPlate)
    recognizedText = "";

    binaryPlate = logical(binaryPlate);
    binaryPlate = imclearborder(binaryPlate);
    binaryPlate = bwareaopen(binaryPlate, 20);

    if nnz(binaryPlate) == 0
        return;
    end

    rowProfile = sum(binaryPlate, 2);
    rowMask = rowProfile > max(rowProfile) * 0.18;

    if any(rowMask)
        rowStarts = find(diff([0; rowMask]) == 1);
        rowEnds = find(diff([rowMask; 0]) == -1);
    else
        rowStarts = 1;
        rowEnds = size(binaryPlate, 1);
    end

    lines = strings(0);

    for r = 1:numel(rowStarts)
        lineImage = binaryPlate(rowStarts(r):rowEnds(r), :);
        lineText = readPlateLine(lineImage);

        if strlength(lineText) > 0
            lines(end + 1) = lineText; %#ok<AGROW>
        end
    end

    if isempty(lines)
        return;
    end

    recognizedText = strjoin(lines, " ");
    recognizedText = formatPlateText(recognizedText);
end

function lineText = readPlateLine(lineImage)
    lineText = "";
    lineImage = imclearborder(lineImage);
    lineImage = bwareaopen(lineImage, 15);

    cc = bwconncomp(lineImage);
    stats = regionprops(cc, 'BoundingBox', 'Area');

    if isempty(stats)
        return;
    end

    boxes = reshape([stats.BoundingBox], 4, []).';
    areas = [stats.Area].';

    keep = false(size(areas));
    for i = 1:numel(areas)
        aspectRatio = boxes(i, 3) / boxes(i, 4);
        if areas(i) >= 15 && areas(i) <= 4000 && aspectRatio >= 0.08 && aspectRatio <= 1.5
            keep(i) = true;
        end
    end

    boxes = boxes(keep, :);

    if isempty(boxes)
        return;
    end

    [~, order] = sort(boxes(:, 1));
    boxes = boxes(order, :);

    chars = strings(0);
    for i = 1:size(boxes, 1)
        charBox = boxes(i, :);
        charImage = imcrop(lineImage, charBox);
        charImage = padarray(charImage, [8 8], 0, 'both');
        charImage = imresize(charImage, [64 48], 'nearest');

        ocrResult = ocr(im2uint8(charImage));
        charText = cleanPlateText(ocrResult.Text);

        if strlength(charText) >= 1
            chars(end + 1) = extractBetween(charText, 1, 1); %#ok<AGROW>
        end
    end

    if ~isempty(chars)
        lineText = join(chars, "");
        lineText = string(lineText);
    end
end

function recognizedText = readPlateByLines(focusedPlate, textRegion, enhancedPlate, binaryPlate)
    recognizedText = "";
    variants = {im2uint8(textRegion), im2uint8(focusedPlate), im2uint8(enhancedPlate), im2uint8(binaryPlate) * 255};
    bestText = "";
    bestScore = -inf;

    for v = 1:numel(variants)
        currentImage = variants{v};
        [rows, ~] = size(currentImage);

        % Whole plate OCR
        wholeResult = ocr(currentImage);
        wholeText = formatPlateText(cleanPlateText(wholeResult.Text));
        wholeScore = plateTextScore(wholeText, meanConfidence(wholeResult));

        if wholeScore > bestScore
            bestScore = wholeScore;
            bestText = wholeText;
        end

        % Two-line OCR for stacked Malaysian plates such as SWC / 333.
        topHalf = currentImage(1:max(1, round(rows * 0.55)), :);
        bottomHalf = currentImage(max(1, round(rows * 0.35)):end, :);

        topResult = ocr(topHalf);
        bottomResult = ocr(bottomHalf);

        topText = cleanPlateText(topResult.Text);
        bottomText = cleanPlateText(bottomResult.Text);

        combinedText = formatPlateText(topText + " " + bottomText);
        combinedScore = plateTextScore(combinedText, mean([meanConfidence(topResult), meanConfidence(bottomResult)], 'omitnan'));

        if combinedScore > bestScore
            bestScore = combinedScore;
            bestText = combinedText;
        end
    end

    recognizedText = bestText;
end

function score = plateTextScore(textValue, confidence)
    score = strlength(textValue) * 10;

    if ~isnan(confidence)
        score = score + confidence / 5;
    end

    if strlength(textValue) >= 3 && strlength(textValue) <= 10
        score = score + 20;
    end

    if any(isstrprop(char(textValue), 'alpha')) && any(isstrprop(char(textValue), 'digit'))
        score = score + 15;
    end

    % Malaysian plates commonly have 1-3 letters followed by 1-4 digits.
    if ~isempty(regexp(char(textValue), '^[A-Z]{1,3}\d{1,4}[A-Z]?$|^[A-Z]{1,3}\s\d{1,4}[A-Z]?$', 'once'))
        score = score + 30;
    end

    % Penalize all-letter outputs like LEHBO when the plate clearly should contain digits.
    if all(isstrprop(char(textValue), 'alpha'))
        score = score - 25;
    end
end

function formattedText = formatPlateText(rawText)
    rawText = upper(string(rawText));
    rawText = regexprep(rawText, '\s+', '');
    rawText = regexprep(rawText, '[^A-Z0-9]', '');

    formattedText = rawText;

    if strlength(rawText) >= 3 && strlength(rawText) <= 10
        firstDigitIndex = regexp(char(rawText), '\d', 'once');

        if ~isempty(firstDigitIndex) && firstDigitIndex > 1
            prefix = extractBetween(rawText, 1, firstDigitIndex - 1);
            suffix = extractAfter(rawText, firstDigitIndex - 1);

            if strlength(prefix) >= 1 && strlength(prefix) <= 3 && ...
                    strlength(suffix) >= 1 && strlength(suffix) <= 4
                formattedText = prefix + " " + suffix;
            end
        end
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
    binaryPlate = bwareaopen(binaryPlate, 25);
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

        if area > 20 && area < 2500 && aspectRatio > 0.08 && aspectRatio < 1.4
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
        % Keep the original image if EXIF orientation is unavailable.
    end
end
