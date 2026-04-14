function result = extractCarPlateFromImage_v1(inputValue)
%EXTRACTCARPLATEFROMIMAGE_V1 Detect and read a vehicle plate region.
% Candidate boxes are generated from simple plate-like structures, then the
% same OCR-variant routine used by the OCR tester chooses the best result.

    if ischar(inputValue) || isstring(inputValue)
        imageData = loadVehicleImage(char(inputValue));
    else
        imageData = inputValue;
    end

    [plateText, plateBox, plateImage, binaryPlate, candidateBoxes, debugReport] = extractCarPlate(imageData);

    result = struct( ...
        'Image', imageData, ...
        'PlateText', string(plateText), ...
        'PlateBox', plateBox, ...
        'PlateImage', plateImage, ...
        'BinaryPlate', binaryPlate, ...
        'CandidateBoxes', candidateBoxes, ...
        'DebugReport', debugReport);
end

function [plateText, bestBox, bestCrop, bestBinary, candidateBoxes, debugReport] = extractCarPlate(imageData)
    grayImage = preprocessVehicleImage(imageData);
    [rows, cols] = size(grayImage);
    debugReport = initDebugReportV1(imageData);
    debugReport = addDebugStepV1(debugReport, 'Step 1 - Preprocessed grayscale', grayImage, ...
        'Converted to grayscale, enhanced contrast with CLAHE, then median filtered.');

    [candidateBoxes, candidateDebug] = generateCandidateBoxes(grayImage);
    debugReport = appendDebugStepsV1(debugReport, candidateDebug);
    debugReport = addDebugStepV1(debugReport, 'Step 8 - Candidate boxes', ...
        overlayBoxesOnImageV1(imageData, candidateBoxes), ...
        sprintf('Candidate regions kept after mask filtering: %d', size(candidateBoxes, 1)));
    if isempty(candidateBoxes)
        plateText = "";
        bestBox = [];
        bestCrop = [];
        bestBinary = [];
        debugReport.Status = "failed";
        debugReport.Notes = "No plate-like candidate boxes survived in v1.";
        return;
    end

    bestScore = -inf;
    bestBox = [];
    bestCrop = [];
    bestBinary = [];
    plateText = "";
    bestCandidateInfo = struct('Text', "", 'Score', -inf, 'Index', 0);

    for i = 1:size(candidateBoxes, 1)
        currentBox = clampBox(candidateBoxes(i, :), rows, cols);
        [score, cropImage, binaryImage, textValue] = evaluateCandidate(imageData, grayImage, currentBox);

        if score > bestScore
            bestScore = score;
            bestBox = currentBox;
            bestCrop = cropImage;
            bestBinary = binaryImage;
            plateText = textValue;
            bestCandidateInfo.Text = textValue;
            bestCandidateInfo.Score = score;
            bestCandidateInfo.Index = i;
        end
    end

    if ~isempty(bestCrop)
        debugReport = addDebugStepV1(debugReport, 'Step 9 - Best candidate crop', bestCrop, ...
            sprintf('Best candidate index %d with OCR text "%s".', ...
            bestCandidateInfo.Index, char(string(bestCandidateInfo.Text))));
    end
    if ~isempty(bestBinary)
        debugReport = addDebugStepV1(debugReport, 'Step 10 - Best binary evidence', bestBinary, ...
            sprintf('Best v1 score: %.2f', bestCandidateInfo.Score));
    end

    if bestScore < 20 || ~isAcceptableFinalPlateTextV1(plateText, bestBox, size(grayImage))
        plateText = "";
        debugReport.Status = "failed";
        debugReport.Notes = sprintf('v1 found candidates, but best score %.2f did not produce usable plate text.', bestScore);
    else
        debugReport.Status = "completed";
        debugReport.Notes = sprintf('v1 selected candidate %d with score %.2f and text "%s".', ...
            bestCandidateInfo.Index, bestScore, char(string(plateText)));
    end
end

function grayImage = preprocessVehicleImage(imageData)
    if ndims(imageData) == 3
        grayImage = rgb2gray(imageData);
    else
        grayImage = imageData;
    end

    grayImage = im2uint8(grayImage);
    grayImage = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.015);
    grayImage = medfilt2(grayImage, [3 3]);
end

function [candidateBoxes, debugSteps] = generateCandidateBoxes(grayImage)
    [rows, cols] = size(grayImage);
    debugSteps = repmat(makeDebugStepV1("", [], ""), 0, 1);

    roiTop = max(1, round(rows * 0.28));
    roiBottom = rows;
    roiLeft = max(1, round(cols * 0.06));
    roiRight = min(cols, round(cols * 0.94));
    roiImage = grayImage(roiTop:roiBottom, roiLeft:roiRight);
    debugSteps(end + 1, 1) = makeDebugStepV1('Step 2 - Search ROI', roiImage, ...
        'Bottom-centered region used for v1 plate localization.');

    edgeMask = edge(roiImage, 'Canny');
    edgeMask = imclose(edgeMask, strel('rectangle', [4 19]));
    edgeMask = imfill(edgeMask, 'holes');
    edgeMask = bwareaopen(edgeMask, 80);
    debugSteps(end + 1, 1) = makeDebugStepV1('Step 3 - Edge mask', edgeMask, ...
        'Canny edges with morphological closing, hole fill, and small object removal.');

    blackhatMask = imbothat(roiImage, strel('rectangle', [9 25]));
    blackhatMask = imbinarize(blackhatMask, graythresh(blackhatMask));
    blackhatMask = imclose(blackhatMask, strel('rectangle', [5 21]));
    blackhatMask = bwareaopen(blackhatMask, 80);
    debugSteps(end + 1, 1) = makeDebugStepV1('Step 4 - Blackhat mask', blackhatMask, ...
        'Highlights dark characters or borders on brighter plate backgrounds.');

    tophatMask = imtophat(roiImage, strel('rectangle', [9 25]));
    tophatMask = imbinarize(tophatMask, graythresh(tophatMask));
    tophatMask = imclose(tophatMask, strel('rectangle', [5 21]));
    tophatMask = bwareaopen(tophatMask, 80);
    debugSteps(end + 1, 1) = makeDebugStepV1('Step 5 - Tophat mask', tophatMask, ...
        'Highlights bright plate regions against darker surroundings.');

    darkMask = roiImage < min(110, round(graythresh(roiImage) * 255) + 20);
    darkMask = imclose(darkMask, strel('rectangle', [5 17]));
    darkMask = imfill(darkMask, 'holes');
    darkMask = bwareaopen(darkMask, 120);
    debugSteps(end + 1, 1) = makeDebugStepV1('Step 6 - Dark region mask', darkMask, ...
        'Thresholded dark structures that may correspond to character bands.');

    brightMask = roiImage > max(145, round(graythresh(roiImage) * 255));
    brightMask = imclose(brightMask, strel('rectangle', [5 17]));
    brightMask = imfill(brightMask, 'holes');
    brightMask = bwareaopen(brightMask, 120);
    debugSteps(end + 1, 1) = makeDebugStepV1('Step 7 - Bright region mask', brightMask, ...
        'Thresholded bright structures that may correspond to plate backgrounds.');

    masks = {edgeMask, blackhatMask, tophatMask, darkMask, brightMask};
    candidateBoxes = zeros(0, 4);

    for i = 1:numel(masks)
        stats = regionprops(masks{i}, 'BoundingBox', 'Area', 'Extent', 'Solidity', 'Centroid');
        for j = 1:numel(stats)
            bbox = stats(j).BoundingBox;
            aspectRatio = bbox(3) / max(bbox(4), 1);
            relativeArea = (bbox(3) * bbox(4)) / numel(roiImage);
            centerX = stats(j).Centroid(1) / size(roiImage, 2);
            centerY = stats(j).Centroid(2) / size(roiImage, 1);

            if aspectRatio < 0.85 || aspectRatio > 6.5
                continue;
            end
            if relativeArea < 0.0015 || relativeArea > 0.14
                continue;
            end
            if stats(j).Extent < 0.15 || stats(j).Solidity < 0.15
                continue;
            end
            if bbox(4) > size(roiImage, 1) * 0.24
                continue;
            end
            if centerX < 0.10 || centerX > 0.90 || centerY < 0.14 || centerY > 0.90
                continue;
            end

            absBox = [bbox(1) + roiLeft - 1, bbox(2) + roiTop - 1, bbox(3), bbox(4)];
            absBox = expandBoundingBox(absBox, rows, cols, 0.06, 0.05);
            candidateBoxes(end + 1, :) = absBox; %#ok<AGROW>
        end
    end

    if isempty(candidateBoxes)
        return;
    end

    candidateBoxes = unique(round(candidateBoxes), 'rows');
    candidateBoxes = mergeOverlappingBoxes(candidateBoxes, rows, cols);
end

function debugReport = initDebugReportV1(imageData)
    debugReport = struct( ...
        'Method', "v1", ...
        'Status', "running", ...
        'Notes', "", ...
        'Steps', repmat(makeDebugStepV1("", [], ""), 0, 1));
    debugReport = addDebugStepV1(debugReport, 'Input image', imageData, ...
        'Original image passed into v1 detector.');
end

function debugReport = addDebugStepV1(debugReport, titleText, imageData, descriptionText)
    debugReport.Steps(end + 1, 1) = makeDebugStepV1(titleText, imageData, descriptionText);
end

function debugReport = appendDebugStepsV1(debugReport, steps)
    if isempty(steps)
        return;
    end
    debugReport.Steps = [debugReport.Steps; steps];
end

function step = makeDebugStepV1(titleText, imageData, descriptionText)
    step = struct( ...
        'Title', string(titleText), ...
        'Image', imageData, ...
        'Description', string(descriptionText));
end

function overlayImage = overlayBoxesOnImageV1(imageData, candidateBoxes)
    if ndims(imageData) == 2
        overlayImage = repmat(im2uint8(imageData), 1, 1, 3);
    else
        overlayImage = im2uint8(imageData);
    end

    if isempty(candidateBoxes)
        return;
    end

    shape = insertShape(overlayImage, 'Rectangle', candidateBoxes, ...
        'Color', 'yellow', 'LineWidth', 3);
    overlayImage = shape;
end

function mergedBoxes = mergeOverlappingBoxes(candidateBoxes, rows, cols)
    mergedBoxes = candidateBoxes;
    changed = true;

    while changed
        changed = false;
        i = 1;
        while i <= size(mergedBoxes, 1)
            j = i + 1;
            while j <= size(mergedBoxes, 1)
                if boxOverlapScore(mergedBoxes(i, :), mergedBoxes(j, :)) > 0.45
                    mergedBoxes(i, :) = mergeTwoBoxes(mergedBoxes(i, :), mergedBoxes(j, :), rows, cols);
                    mergedBoxes(j, :) = [];
                    changed = true;
                else
                    j = j + 1;
                end
            end
            i = i + 1;
        end
    end
end

function score = boxOverlapScore(boxA, boxB)
    ax1 = boxA(1); ay1 = boxA(2);
    ax2 = boxA(1) + boxA(3); ay2 = boxA(2) + boxA(4);
    bx1 = boxB(1); by1 = boxB(2);
    bx2 = boxB(1) + boxB(3); by2 = boxB(2) + boxB(4);

    interW = max(0, min(ax2, bx2) - max(ax1, bx1));
    interH = max(0, min(ay2, by2) - max(ay1, by1));
    interArea = interW * interH;
    unionArea = boxA(3) * boxA(4) + boxB(3) * boxB(4) - interArea;

    if unionArea <= 0
        score = 0;
    else
        score = interArea / unionArea;
    end
end

function mergedBox = mergeTwoBoxes(boxA, boxB, rows, cols)
    x1 = min(boxA(1), boxB(1));
    y1 = min(boxA(2), boxB(2));
    x2 = max(boxA(1) + boxA(3), boxB(1) + boxB(3));
    y2 = max(boxA(2) + boxA(4), boxB(2) + boxB(4));
    mergedBox = clampBox([x1, y1, x2 - x1, y2 - y1], rows, cols);
end

function [score, finalCrop, finalBinary, recognizedText] = evaluateCandidate(imageData, grayImage, candidateBox)
    [rows, cols] = size(grayImage);
    originalBox = clampBox(candidateBox, rows, cols);
    tightenedBox = tightenBoxByCharacterBand(grayImage, originalBox);
    tightenedBox = clampBox(tightenedBox, rows, cols);

    candidateBoxes = originalBox;
    if isUsefulTightenedBoxV1(originalBox, tightenedBox)
        candidateBoxes = [candidateBoxes; tightenedBox];
    end

    bestLocalScore = -inf;
    finalCrop = [];
    finalBinary = [];
    recognizedText = "";

    for optionIndex = 1:size(candidateBoxes, 1)
        currentBox = candidateBoxes(optionIndex, :);
        [currentScore, currentCrop, currentBinary, currentText] = ...
            scoreSingleCandidateCropV1(imageData, grayImage, currentBox, originalBox, optionIndex == 1);

        if currentScore > bestLocalScore
            bestLocalScore = currentScore;
            finalCrop = currentCrop;
            finalBinary = currentBinary;
            recognizedText = currentText;
        end
    end

    score = bestLocalScore;
end

function [score, cropOriginal, finalBinary, recognizedText] = ...
        scoreSingleCandidateCropV1(imageData, grayImage, candidateBox, originalBox, preferFullBox)
    [rows, cols] = size(grayImage);

    if candidateBox(3) < cols * 0.035 || candidateBox(4) < rows * 0.02
        score = -inf;
        cropOriginal = [];
        finalBinary = [];
        recognizedText = "";
        return;
    end

    cropOriginal = safeCrop(imageData, candidateBox);
    cropGray = safeCrop(grayImage, candidateBox);
    if isempty(cropOriginal) || isempty(cropGray)
        score = -inf;
        cropOriginal = [];
        finalBinary = [];
        recognizedText = "";
        return;
    end

    variantImages = runDirectVariantOCR(cropOriginal);
    [recognizedText, ~, finalBinary, score] = readPlateTextMultiV1(variantImages);
    score = score + plateStructureScore(cropGray, finalBinary);
    [coverageScore, coverageNotes] = fullPlateOccupancyScoreV1(finalBinary);
    score = score + coverageScore;
    score = score + positionScoreV1(candidateBox, size(grayImage));

    charCount = countCharacterLikeComponents(finalBinary);
    twoLineFlag = detectTwoLineFromBinaryV1(finalBinary);
    if charCount < 2
        score = score - 50;
    elseif charCount < 4
        score = score - 20;
    elseif charCount <= 10
        score = score + charCount * 4;
    end
    if twoLineFlag
        score = score + 18;
    end

    aspectRatio = candidateBox(3) / max(candidateBox(4), 1);
    if aspectRatio >= 1.2 && aspectRatio <= 7.5
        score = score + 10;
    end

    widthRetention = candidateBox(3) / max(originalBox(3), 1);
    heightRetention = candidateBox(4) / max(originalBox(4), 1);
    relativeWidth = candidateBox(3) / max(cols, 1);

    if ~preferFullBox && (widthRetention < 0.80 || heightRetention < 0.60)
        score = score - 120;
    end

    if widthRetention < 0.72
        score = score - 55;
    elseif widthRetention < 0.85
        score = score - 20;
    elseif widthRetention < 0.93
        score = score - 12;
    end

    if heightRetention < 0.55
        score = score - 25;
    elseif heightRetention < 0.70
        score = score - 10;
    end

    if relativeWidth < 0.16
        score = score - 45;
    elseif relativeWidth < 0.22
        score = score - 20;
    end

    if preferFullBox
        score = score + 28;
    else
        score = score - 20;
    end

    score = score + foregroundCoverageScoreV1(finalBinary);
    score = score + characterBandScoreV1(finalBinary);
    score = score + plateBodyScoreV1(finalBinary);

    if strlength(recognizedText) > 0
        score = score + textLengthScoreV1(recognizedText);

        if ~(any(isstrprop(char(recognizedText), 'alpha')) && any(isstrprop(char(recognizedText), 'digit')))
            score = score - 55;
        end

        if isLikelyPlateTextV1(recognizedText)
            score = score + 35;
        else
            score = score - 50;
        end
    end

    if strlength(recognizedText) == 0
        score = score - 120;
    end
end

function score = plateStructureScore(grayCrop, binaryPlate)
    score = 0;
    grayCrop = im2uint8(grayCrop);
    binaryPlate = logical(binaryPlate);

    aspectRatio = size(grayCrop, 2) / max(size(grayCrop, 1), 1);
    if aspectRatio >= 1.0 && aspectRatio <= 7.5
        score = score + 15;
    else
        score = score - 20;
    end

    fillRatio = nnz(binaryPlate) / max(numel(binaryPlate), 1);
    if fillRatio >= 0.06 && fillRatio <= 0.55
        score = score + 15;
    else
        score = score - 15;
    end

    edgeMask = edge(grayCrop, 'Canny');
    edgeDensity = nnz(edgeMask) / max(numel(edgeMask), 1);
    if edgeDensity >= 0.02 && edgeDensity <= 0.30
        score = score + 12;
    else
        score = score - 10;
    end

    darkFraction = mean(grayCrop(:) < 110);
    brightFraction = mean(grayCrop(:) > 145);
    if darkFraction > 0.10 && brightFraction > 0.10
        score = score + 10;
    end
end

function score = plateBodyScoreV1(binaryImage)
    score = 0;
    binaryImage = logical(binaryImage);
    if ~any(binaryImage(:))
        score = score - 35;
        return;
    end

    fillRatio = nnz(binaryImage) / max(numel(binaryImage), 1);
    centerBand = binaryImage(max(1, round(end * 0.25)):min(size(binaryImage, 1), round(end * 0.75)), :);
    centerFill = nnz(centerBand) / max(numel(centerBand), 1);
    charCount = countCharacterLikeComponents(binaryImage);

    if fillRatio < 0.03 || fillRatio > 0.65
        score = score - 20;
    end

    if centerFill >= 0.03 && centerFill <= 0.35
        score = score + 12;
    else
        score = score - 15;
    end

    if charCount >= 4
        score = score + 14;
    elseif charCount <= 2
        score = score - 25;
    end
end

function [score, notes] = fullPlateOccupancyScoreV1(binaryImage)
    score = 0;
    notes = "";
    if isempty(binaryImage)
        score = score - 80;
        notes = "Empty binary evidence.";
        return;
    end

    binaryImage = logical(binaryImage);
    binaryImage = imclearborder(binaryImage);
    binaryImage = bwareaopen(binaryImage, 12);
    if nnz(binaryImage) == 0
        score = score - 80;
        notes = "No foreground after cleanup.";
        return;
    end

    stats = regionprops(binaryImage, 'BoundingBox', 'Area', 'Centroid');
    boxes = reshape([stats.BoundingBox], 4, []).';
    areas = [stats.Area]';
    heights = boxes(:, 4);
    widths = boxes(:, 3);
    aspect = widths ./ max(heights, 1);
    keep = areas > 10 & areas < 6000 & aspect > 0.08 & aspect < 1.6;
    boxes = boxes(keep, :);

    if isempty(boxes) || size(boxes, 1) < 3
        score = score - 65;
        notes = "Too few character-like blobs.";
        return;
    end

    unionBox = unionBoxesV1(boxes);
    cropArea = numel(binaryImage);
    unionArea = unionBox(3) * unionBox(4);
    widthRatio = unionBox(3) / size(binaryImage, 2);
    heightRatio = unionBox(4) / size(binaryImage, 1);
    areaRatio = unionArea / cropArea;

    if widthRatio < 0.35 || heightRatio < 0.20 || areaRatio < 0.08
        score = score - 60;
        notes = "Character union too small for full plate coverage.";
        return;
    end

    marginLeft = unionBox(1);
    marginTop = unionBox(2);
    marginRight = size(binaryImage, 2) - (unionBox(1) + unionBox(3));
    marginBottom = size(binaryImage, 1) - (unionBox(2) + unionBox(4));
    if min([marginLeft marginRight marginTop marginBottom]) < 2
        score = score - 30;
        notes = "Character union touches border.";
    else
        score = score + 22;
    end
end

function unionBox = unionBoxesV1(boxes)
    x1 = min(boxes(:, 1));
    y1 = min(boxes(:, 2));
    x2 = max(boxes(:, 1) + boxes(:, 3));
    y2 = max(boxes(:, 2) + boxes(:, 4));
    unionBox = [x1 y1 x2 - x1 y2 - y1];
end

function tf = detectTwoLineFromBinaryV1(binaryImage)
    tf = false;
    if isempty(binaryImage)
        return;
    end
    binaryImage = logical(binaryImage);
    binaryImage = bwareaopen(binaryImage, 12);
    stats = regionprops(binaryImage, 'BoundingBox', 'Area', 'Centroid');
    if numel(stats) < 3
        return;
    end
    centersY = reshape([stats.Centroid], 2, []).';
    centersY = centersY(:, 2);
    [~, order] = sort(centersY);
    centersY = centersY(order);
    splitIndex = round(numel(centersY) / 2);
    upperMean = mean(centersY(1:splitIndex));
    lowerMean = mean(centersY(splitIndex + 1:end));
    if lowerMean - upperMean < size(binaryImage, 1) * 0.18
        return;
    end
    upperCount = sum(centersY <= upperMean + size(binaryImage, 1) * 0.15);
    lowerCount = sum(centersY >= lowerMean - size(binaryImage, 1) * 0.15);
    tf = upperCount >= 2 && lowerCount >= 1;
end

function score = positionScoreV1(candidateBox, imageSize)
    imageHeight = imageSize(1);
    imageWidth = imageSize(2);
    boxCenterX = (candidateBox(1) + candidateBox(3) / 2) / imageWidth;
    boxCenterY = (candidateBox(2) + candidateBox(4) / 2) / imageHeight;

    score = -abs(boxCenterX - 0.5) * 70;
    if boxCenterY >= 0.32 && boxCenterY <= 0.86
        score = score + 10;
    elseif boxCenterY < 0.22 || boxCenterY > 0.92
        score = score - 35;
    end

    if (boxCenterX < 0.20 || boxCenterX > 0.80) && boxCenterY > 0.82
        score = score - 30;
    end
end

function score = textLengthScoreV1(textValue)
    textLength = strlength(string(textValue));
    if textLength == 0
        score = -120;
    elseif textLength == 1
        score = -120;
    elseif textLength <= 3
        if isStrictShortPlateTextV1(textValue)
            score = 5;
        else
            score = -80;
        end
    elseif textLength <= 8
        score = 15;
    else
        score = -30;
    end
end

function variantImages = runDirectVariantOCR(cropImage)
    if ndims(cropImage) == 3
        grayImage = rgb2gray(cropImage);
    else
        grayImage = cropImage;
    end

    grayImage = im2uint8(grayImage);
    enhanced = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.02);
    sharpened = imsharpen(enhanced, 'Radius', 1.0, 'Amount', 1.2);
    upscaledGray2 = imresize(grayImage, 2.0, 'bicubic');
    upscaledSharp2 = imresize(sharpened, 2.0, 'bicubic');
    upscaledGray3 = imresize(grayImage, 3.0, 'bicubic');
    upscaledSharp3 = imresize(sharpened, 3.0, 'bicubic');

    darkText = imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    darkText = cleanBinaryPlate(darkText);

    brightText = imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
    brightText = cleanBinaryPlate(brightText);

    darkTextUpscaled2 = imbinarize(upscaledSharp2, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    darkTextUpscaled2 = cleanBinaryPlate(darkTextUpscaled2);
    darkTextUpscaled3 = imbinarize(upscaledSharp3, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    darkTextUpscaled3 = cleanBinaryPlate(darkTextUpscaled3);

    invertedImage = imcomplement(sharpened);

    variantImages = {
        grayImage
        enhanced
        sharpened
        darkText
        brightText
        invertedImage
        upscaledGray2
        upscaledSharp2
        darkTextUpscaled2
        upscaledGray3
        upscaledSharp3
        darkTextUpscaled3
    };
end

function [bestText, bestVariant, bestBinary, bestScore] = readPlateTextMultiV1(variantImages)
    bestText = "";
    bestVariant = [];
    bestBinary = [];
    bestScore = -inf;

    for i = 1:numel(variantImages)
        currentVariant = variantImages{i};
        ocrInput = im2uint8(currentVariant);

        [currentText, currentScore] = readOCRVariantV1(ocrInput);
        if currentScore > bestScore
            bestScore = currentScore;
            bestText = currentText;
            bestVariant = currentVariant;
            if islogical(currentVariant)
                bestBinary = currentVariant;
            else
                bestBinary = imbinarize(ocrInput, 'adaptive', ...
                    'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
                bestBinary = cleanBinaryPlate(bestBinary);
            end
        end
    end
end

function [bestText, bestScore] = readOCRVariantV1(ocrInput)
    candidates = strings(0, 1);
    scores = [];

    try
        result = runOCRWithFallbackV1(ocrInput);
        textValue = postCorrectPlateTextV1(formatDirectOCRText(result.Text));
        candidates(end + 1, 1) = textValue; %#ok<AGROW>
        scores(end + 1, 1) = scoreDirectOCRText(textValue, result); %#ok<AGROW>
    catch err
        warning('PlateOCR:v1VariantOCR', 'v1 OCR variant failed: %s', err.message);
    end

    if size(ocrInput, 1) >= size(ocrInput, 2) * 0.55
        try
            [lineText, lineScore] = readTwoLineDirectOCR(ocrInput);
            lineText = postCorrectPlateTextV1(lineText);
            candidates(end + 1, 1) = lineText; %#ok<AGROW>
            scores(end + 1, 1) = lineScore; %#ok<AGROW>
        catch err
            warning('PlateOCR:v1TwoLineOCR', 'v1 two-line OCR failed: %s', err.message);
        end
    end

    if isempty(scores)
        bestText = "";
        bestScore = -80;
        return;
    end

    [bestScore, idx] = max(scores);
    bestText = candidates(idx);
end

function [textValue, score] = readTwoLineDirectOCR(imageData)
    rows = size(imageData, 1);
    topHalf = imageData(1:max(1, round(rows * 0.58)), :);
    bottomHalf = imageData(max(1, round(rows * 0.32)):end, :);

    topResult = runOCRWithFallbackV1(topHalf);
    bottomResult = runOCRWithFallbackV1(bottomHalf);

    mergedText = formatDirectOCRText(cleanPlateText(topResult.Text) + cleanPlateText(bottomResult.Text));
    mergedText = postCorrectPlateTextV1(mergedText);
    textValue = mergedText;
    score = scoreDirectOCRText(mergedText, topResult) + scoreDirectOCRText(mergedText, bottomResult) * 0.35;
end

function textValue = formatDirectOCRText(rawText)
    textValue = upper(string(rawText));
    textValue = regexprep(textValue, '[^A-Z0-9]', '');
    textValue = extractBestPlateSubstring(textValue);
end

function score = scoreDirectOCRText(textValue, ocrResult)
    score = strlength(textValue) * 10;

    if ~isempty(ocrResult.CharacterConfidences)
        score = score + mean(ocrResult.CharacterConfidences, 'omitnan') / 5;
    end
    if strlength(textValue) >= 3 && strlength(textValue) <= 10
        score = score + 20;
    end
    if strlength(textValue) >= 5 && strlength(textValue) <= 8
        score = score + 15;
    elseif strlength(textValue) >= 2 && strlength(textValue) <= 4
        score = score + 4;
    end
    if any(isstrprop(char(textValue), 'alpha')) && any(isstrprop(char(textValue), 'digit'))
        score = score + 20;
    end
    if isLikelyPlateTextV1(textValue)
        score = score + 25;
    elseif isStrictShortPlateTextV1(textValue)
        score = score + 8;
    end
end

function result = runOCRWithFallbackV1(ocrInput)
    try
        result = ocr(ocrInput, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', 'TextLayout', 'Word');
        return;
    catch
    end

    try
        result = ocr(ocrInput, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
        return;
    catch
    end

    result = ocr(ocrInput);
end

function tightenedBox = tightenBoxByCharacterBand(grayImage, initialBox)
    [rows, cols] = size(grayImage);
    localCrop = safeCrop(grayImage, initialBox);
    if isempty(localCrop)
        tightenedBox = initialBox;
        return;
    end

    localCrop = im2uint8(localCrop);
    darkMask = localCrop < 170;
    brightMask = localCrop > 145;
    edgeMask = edge(localCrop, 'Canny');
    supportMask = darkMask | brightMask | edgeMask;
    supportMask = imclose(supportMask, strel('rectangle', [3 9]));
    supportMask = bwareaopen(supportMask, 15);

    rowProfile = sum(supportMask, 2);
    colProfile = sum(supportMask, 1);
    if max(rowProfile) <= 0 || max(colProfile) <= 0
        tightenedBox = initialBox;
        return;
    end

    rowMask = rowProfile >= max(rowProfile) * 0.30;
    colMask = colProfile >= max(colProfile) * 0.22;
    [rowStart, rowEnd] = findDominantSpan(double(rowMask(:)), 0.5, max(6, round(size(localCrop, 1) * 0.22)));
    [colStart, colEnd] = findDominantSpan(double(colMask(:)), 0.5, max(10, round(size(localCrop, 2) * 0.35)));

    if isempty(rowStart) || isempty(colStart)
        tightenedBox = initialBox;
        return;
    end

    x1 = max(1, floor(initialBox(1) + colStart - 1 - size(localCrop, 2) * 0.04));
    y1 = max(1, floor(initialBox(2) + rowStart - 1 - size(localCrop, 1) * 0.08));
    x2 = min(cols, ceil(initialBox(1) + colEnd - 1 + size(localCrop, 2) * 0.04));
    y2 = min(rows, ceil(initialBox(2) + rowEnd - 1 + size(localCrop, 1) * 0.08));

    tightenedBox = [x1, y1, x2 - x1, y2 - y1];
    tightenedAspect = tightenedBox(3) / max(tightenedBox(4), 1);
    if tightenedBox(3) < initialBox(3) * 0.72 || ...
            tightenedBox(4) < initialBox(4) * 0.55 || ...
            tightenedAspect < 1.6
        tightenedBox = initialBox;
    end
end

function tf = isUsefulTightenedBoxV1(originalBox, tightenedBox)
    tf = any(abs(tightenedBox - originalBox) > 2);
    if ~tf
        return;
    end

    widthRetention = tightenedBox(3) / max(originalBox(3), 1);
    heightRetention = tightenedBox(4) / max(originalBox(4), 1);
    areaRetention = (tightenedBox(3) * tightenedBox(4)) / max(originalBox(3) * originalBox(4), 1);
    aspectRatio = tightenedBox(3) / max(tightenedBox(4), 1);

    tf = widthRetention >= 0.88 && heightRetention >= 0.60 && ...
        areaRetention >= 0.58 && aspectRatio >= 1.2 && aspectRatio <= 8.0;
end

function score = foregroundCoverageScoreV1(binaryImage)
    score = 0;
    binaryImage = logical(binaryImage);
    if ~any(binaryImage(:))
        score = score - 20;
        return;
    end

    props = regionprops(binaryImage, 'BoundingBox');
    boxes = reshape([props.BoundingBox], 4, []).';
    if isempty(boxes)
        score = score - 20;
        return;
    end

    x1 = min(boxes(:, 1));
    y1 = min(boxes(:, 2));
    x2 = max(boxes(:, 1) + boxes(:, 3));
    y2 = max(boxes(:, 2) + boxes(:, 4));

    widthCoverage = (x2 - x1) / max(size(binaryImage, 2), 1);
    heightCoverage = (y2 - y1) / max(size(binaryImage, 1), 1);
    centerX = ((x1 + x2) / 2) / max(size(binaryImage, 2), 1);
    centerY = ((y1 + y2) / 2) / max(size(binaryImage, 1), 1);

    if widthCoverage >= 0.35 && widthCoverage <= 0.95
        score = score + 12;
    else
        score = score - 18;
    end

    if heightCoverage >= 0.22 && heightCoverage <= 0.82
        score = score + 8;
    else
        score = score - 10;
    end

    if centerX >= 0.22 && centerX <= 0.78
        score = score + 6;
    else
        score = score - 8;
    end

    if centerY >= 0.25 && centerY <= 0.75
        score = score + 6;
    else
        score = score - 8;
    end
end

function score = characterBandScoreV1(binaryImage)
    score = 0;
    binaryImage = logical(binaryImage);
    if ~any(binaryImage(:))
        score = score - 20;
        return;
    end

    stats = regionprops(binaryImage, 'BoundingBox', 'Area', 'Centroid');
    validCentersY = [];
    validWidths = [];
    for i = 1:numel(stats)
        box = stats(i).BoundingBox;
        area = stats(i).Area;
        aspectRatio = box(3) / max(box(4), 1);
        if area >= 20 && area <= 2500 && aspectRatio >= 0.08 && aspectRatio <= 1.4
            validCentersY(end + 1, 1) = stats(i).Centroid(2); %#ok<AGROW>
            validWidths(end + 1, 1) = box(3); %#ok<AGROW>
        end
    end

    count = numel(validCentersY);
    if count < 4
        score = score - 45;
        return;
    end

    ySpread = std(validCentersY) / max(size(binaryImage, 1), 1);
    if ySpread <= 0.11
        score = score + 18;
    elseif ySpread <= 0.20
        score = score + 4;
    else
        score = score - 20;
    end

    if mean(validWidths, 'omitnan') / max(size(binaryImage, 2), 1) <= 0.22
        score = score + 8;
    else
        score = score - 8;
    end
end

function tf = isUsablePlateTextV1(textValue)
    cleanedText = upper(string(textValue));
    cleanedText = regexprep(cleanedText, '[^A-Z0-9]', '');
    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        tf = false;
        return;
    end

    hasAlpha = any(isstrprop(char(cleanedText), 'alpha'));
    hasDigit = any(isstrprop(char(cleanedText), 'digit'));
    tf = hasAlpha && hasDigit;
end

function tf = isAcceptableFinalPlateTextV1(textValue, candidateBox, imageSize)
    textValue = cleanPlateText(textValue);
    tf = false;
    if strlength(textValue) == 0 || isempty(candidateBox)
        return;
    end

    if strlength(textValue) >= 4 && isLikelyPlateTextV1(textValue)
        tf = true;
        return;
    end

    if ~isStrictShortPlateTextV1(textValue)
        return;
    end

    aspectRatio = candidateBox(3) / max(candidateBox(4), 1);
    centerX = (candidateBox(1) + candidateBox(3) / 2) / imageSize(2);
    centerY = (candidateBox(2) + candidateBox(4) / 2) / imageSize(1);
    tf = aspectRatio >= 0.8 && aspectRatio <= 5.5 && ...
        centerX >= 0.28 && centerX <= 0.72 && centerY >= 0.28 && centerY <= 0.88;
end

function tf = isStrictShortPlateTextV1(textValue)
    textValue = cleanPlateText(textValue);
    tf = ~isempty(regexp(char(textValue), '^[A-Z]\d{2,4}$', 'once'));
end

function [spanStart, spanEnd] = findDominantSpan(profileValues, threshold, minLength)
    spanStart = [];
    spanEnd = [];

    if isempty(profileValues) || max(profileValues) <= 0
        return;
    end

    activeMask = profileValues >= threshold;
    if ~any(activeMask)
        [~, peakIndex] = max(profileValues);
        halfWidth = max(1, round(minLength / 2));
        spanStart = max(1, peakIndex - halfWidth);
        spanEnd = min(numel(profileValues), peakIndex + halfWidth);
        return;
    end

    starts = find(diff([0; activeMask(:)]) == 1);
    ends = find(diff([activeMask(:); 0]) == -1);
    bestScore = -inf;

    for i = 1:numel(starts)
        currentStart = starts(i);
        currentEnd = ends(i);
        currentScore = sum(profileValues(currentStart:currentEnd));

        if (currentEnd - currentStart + 1) < minLength
            pad = ceil((minLength - (currentEnd - currentStart + 1)) / 2);
            currentStart = max(1, currentStart - pad);
            currentEnd = min(numel(profileValues), currentEnd + pad);
            currentScore = sum(profileValues(currentStart:currentEnd));
        end

        if currentScore > bestScore
            bestScore = currentScore;
            spanStart = currentStart;
            spanEnd = currentEnd;
        end
    end
end

function binaryPlate = cleanBinaryPlate(binaryPlate)
    binaryPlate = imclearborder(binaryPlate);
    binaryPlate = bwareaopen(binaryPlate, 8);
    binaryPlate = imclose(binaryPlate, strel('rectangle', [2 2]));
end

function charCount = countCharacterLikeComponents(binaryImage)
    cc = bwconncomp(binaryImage);
    stats = regionprops(cc, 'BoundingBox', 'Area');
    charCount = 0;

    for i = 1:numel(stats)
        box = stats(i).BoundingBox;
        area = stats(i).Area;
        aspectRatio = box(3) / max(box(4), 1);
        if area >= 20 && area <= 2500 && aspectRatio >= 0.08 && aspectRatio <= 1.4
            charCount = charCount + 1;
        end
    end
end

function expandedBox = expandBoundingBox(bbox, rows, cols, yPadRatio, xPadRatio)
    x1 = max(1, floor(bbox(1) - bbox(3) * xPadRatio));
    y1 = max(1, floor(bbox(2) - bbox(4) * yPadRatio));
    x2 = min(cols, ceil(bbox(1) + bbox(3) + bbox(3) * xPadRatio));
    y2 = min(rows, ceil(bbox(2) + bbox(4) + bbox(4) * yPadRatio));
    expandedBox = [x1, y1, x2 - x1, y2 - y1];
end

function clampedBox = clampBox(box, rows, cols)
    x1 = max(1, floor(box(1)));
    y1 = max(1, floor(box(2)));
    x2 = min(cols, ceil(box(1) + box(3)));
    y2 = min(rows, ceil(box(2) + box(4)));
    clampedBox = [x1, y1, max(1, x2 - x1), max(1, y2 - y1)];
end

function cropImage = safeCrop(imageData, roi)
    roi = round(roi);
    x1 = max(1, roi(1));
    y1 = max(1, roi(2));
    x2 = min(size(imageData, 2), x1 + max(1, roi(3)) - 1);
    y2 = min(size(imageData, 1), y1 + max(1, roi(4)) - 1);

    if x2 <= x1 || y2 <= y1
        cropImage = [];
    else
        cropImage = imageData(y1:y2, x1:x2, :);
    end
end

function bestText = extractBestPlateSubstring(rawText)
    rawText = string(rawText);
    bestText = rawText;
    bestScore = -inf;

    if strlength(rawText) == 0
        return;
    end

    candidateMatches = regexp(char(rawText), '[A-Z]\d{1,4}|[A-Z]{1,3}\d{1,4}[A-Z]?|\d{1,4}[A-Z]{1,3}', 'match');
    if isempty(candidateMatches)
        candidateMatches = {char(rawText)};
    end

    for i = 1:numel(candidateMatches)
        candidate = string(candidateMatches{i});
        score = strlength(candidate) * 10;
        if isLikelyPlateTextV1(candidate)
            score = score + 40;
        elseif isStrictShortPlateTextV1(candidate)
            score = score + 10;
        end
        if any(isstrprop(char(candidate), 'alpha')) && any(isstrprop(char(candidate), 'digit'))
            score = score + 20;
        end
        if strlength(candidate) >= 5 && strlength(candidate) <= 8
            score = score + 20;
        elseif strlength(candidate) >= 2 && strlength(candidate) <= 4
            score = score + 6;
        end

        if score > bestScore
            bestScore = score;
            bestText = candidate;
        end
    end
end

function cleanedText = cleanPlateText(rawText)
    cleanedText = upper(string(rawText));
    cleanedText = regexprep(cleanedText, '[^A-Z0-9]', '');
end

function tf = isLikelyPlateTextV1(textValue)
    textValue = cleanPlateText(textValue);
    if strlength(textValue) >= 4
        tf = ~isempty(regexp(char(textValue), ...
            '^[A-Z]{1,3}\d{1,4}[A-Z]?$|^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$', 'once'));
    else
        tf = isStrictShortPlateTextV1(textValue);
    end
end

function textValue = postCorrectPlateTextV1(textValue)
    textValue = upper(string(textValue));
    textValue = regexprep(textValue, '[^A-Z0-9]', '');
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

    bestText = textValue;
    bestScore = -inf;
    for i = 1:numel(candidates)
        current = upper(string(candidates(i)));
        current = regexprep(current, '[^A-Z0-9]', '');
        score = strlength(current) * 5;
        if isUsablePlateTextV1(current)
            score = score + 30;
        end
        if any(isstrprop(char(current), 'alpha')) && any(isstrprop(char(current), 'digit'))
            score = score + 15;
        end
        if isLikelyPlateTextV1(current)
            score = score + 40;
        elseif isStrictShortPlateTextV1(current)
            score = score + 12;
        end
        if score > bestScore
            bestScore = score;
            bestText = current;
        end
    end
    textValue = bestText;
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
    end
end
