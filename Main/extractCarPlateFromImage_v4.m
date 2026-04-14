function result = extractCarPlateFromImage_v4(inputValue)
%EXTRACTCARPLATEFROMIMAGE_V4 Text-group-first classical plate extractor.

    if ischar(inputValue) || isstring(inputValue)
        imageData = imread(char(inputValue));
    else
        imageData = inputValue;
    end

    [plateText, plateBox, plateImage, binaryPlate, candidateBoxes, debugReport] = detectPlateV4(imageData);

    result = struct( ...
        'Image', imageData, ...
        'PlateText', string(plateText), ...
        'PlateBox', plateBox, ...
        'PlateImage', plateImage, ...
        'BinaryPlate', binaryPlate, ...
        'CandidateBoxes', candidateBoxes, ...
        'DebugReport', debugReport);
end

function [plateText, bestBox, bestCrop, bestBinary, candidateBoxes, debugReport] = detectPlateV4(imageData)
    debugReport = initDebugReportV4(imageData);
    [grayImage, enhancedImage] = preprocessVehicleImageV4(imageData);
    [rows, cols] = size(enhancedImage);

    debugReport = addDebugStepV4(debugReport, 'Step 1 - Grayscale', grayImage, ...
        'Converted to grayscale, denoised lightly, and normalized to uint8.');
    debugReport = addDebugStepV4(debugReport, 'Step 2 - Enhanced image', enhancedImage, ...
        'CLAHE plus mild sharpening to improve local character contrast.');

    roiBox = buildSearchROIV4(rows, cols);
    roiImage = imcrop(enhancedImage, roiBox);
    debugReport = addDebugStepV4(debugReport, 'Step 3 - Search ROI', roiImage, ...
        'Center-guided vehicle ROI with preference for typical front or rear plate zones.');

    [componentTable, componentDebug] = detectCharacterComponentsV4(roiImage, roiBox, enhancedImage);
    debugReport = appendDebugStepsV4(debugReport, componentDebug);

    plateText = "";
    bestBox = [];
    bestCrop = [];
    bestBinary = [];
    candidateBoxes = zeros(0, 4);

    if isempty(componentTable)
        debugReport.Status = "failed";
        debugReport.Notes = "v4 did not find enough character-like components to build a plate group.";
        return;
    end

    componentBoxes = vertcat(componentTable.Box);
    debugReport = addDebugStepV4(debugReport, 'Step 7 - Character components', ...
        overlayBoxesOnImageV4(imageData, componentBoxes, [0 255 255]), ...
        sprintf('Character-like components kept after filtering: %d', numel(componentTable)));

    candidateGroups = groupCharacterComponentsV4(componentTable, roiBox);
    if isempty(candidateGroups)
        candidateBoxes = componentBoxes;
        debugReport.Status = "failed";
        debugReport.Notes = "v4 found character-like components, but they did not form a stable plate text group.";
        return;
    end

    for i = 1:numel(candidateGroups)
        [structureScore, supportInfo] = scoreCandidateStructureV4(enhancedImage, candidateGroups(i).Box, ...
            componentTable, roiBox, candidateGroups(i).RowCount);
        candidateGroups(i).StructureScore = structureScore; %#ok<AGROW>
        candidateGroups(i).Support = supportInfo; %#ok<AGROW>
        candidateGroups(i).Score = candidateGroups(i).Score + structureScore; %#ok<AGROW>
    end

    [~, sortIdx] = sort([candidateGroups.Score], 'descend');
    candidateGroups = candidateGroups(sortIdx);
    candidateBoxes = vertcat(candidateGroups.Box);
    topCandidateBoxes = candidateBoxes(1:min(10, size(candidateBoxes, 1)), :);
    debugReport = addDebugStepV4(debugReport, 'Step 8 - Grouped text candidates', ...
        overlayBoxesOnImageV4(imageData, topCandidateBoxes, [255 215 0]), ...
        sprintf('Grouped %d plate-band candidates from aligned character components.', numel(candidateGroups)));

    bestCandidateScore = -inf;
    bestVariantStrip = [];
    bestVariantNote = "";
    selectedGroupIndex = 0;

    maxCandidatesToOCR = min(6, numel(candidateGroups));
    for i = 1:maxCandidatesToOCR
        currentGroup = candidateGroups(i);
        allowNormalization = i <= 2;
        [candidateText, candidateScore, cropImage, binaryImage, variantStrip, variantNote, sanityPass] = ...
            runOCROnGroupedCandidateV4(grayImage, currentGroup, roiBox, allowNormalization);

        totalScore = currentGroup.Score + candidateScore;
        if ~sanityPass
            totalScore = totalScore - 120;
        end
        if totalScore > bestCandidateScore
            bestCandidateScore = totalScore;
            bestBox = currentGroup.Box;
            bestCrop = cropImage;
            bestBinary = binaryImage;
            plateText = candidateText;
            bestVariantStrip = variantStrip;
            bestVariantNote = variantNote;
            selectedGroupIndex = i;
        end
    end

    chosenOverlay = overlayBoxesOnImageV4(imageData, topCandidateBoxes, [255 180 0]);
    if ~isempty(bestBox)
        chosenOverlay = insertShape(chosenOverlay, 'Rectangle', bestBox, ...
            'Color', 'green', 'LineWidth', 4);
    end
    debugReport = addDebugStepV4(debugReport, 'Step 9 - Chosen candidate group', chosenOverlay, ...
        sprintf('Top OCR-tested group index: %d. Best combined score: %.2f.', selectedGroupIndex, bestCandidateScore));

    if ~isempty(bestCrop)
        debugReport = addDebugStepV4(debugReport, 'Step 10 - Best crop', bestCrop, ...
            sprintf('Best OCR text after grouping-first localization: "%s".', char(string(plateText))));
    end
    if ~isempty(bestBinary)
        debugReport = addDebugStepV4(debugReport, 'Step 11 - Best OCR input', bestBinary, ...
            'Best OCR preprocessing view selected from grayscale, binary, and inverted variants.');
    end
    if ~isempty(bestVariantStrip)
        debugReport = addDebugStepV4(debugReport, 'Step 12 - OCR variants tested', bestVariantStrip, bestVariantNote);
    end

    rejectionReason = "";
    classification = classifyMalaysianPlateReadV4(plateText);
    if ~classification.IsStrongValid
        if ~isempty(bestBox) && classification.IsPlausiblePartial
            debugReport.Status = "failed";
            debugReport.Notes = sprintf('v4 localized a plausible plate band, but OCR text "%s" did not pass strict Malaysian plate validation.', ...
                char(string(plateText)));
            plateText = "";
            rejectionReason = "plausible-partial";
        else
            plateText = "";
            bestBox = [];
            bestCrop = [];
            bestBinary = [];
            debugReport.Status = "failed";
            debugReport.Notes = "v4 tested grouped text candidates, but none produced an approved Malaysian plate read.";
            rejectionReason = "invalid-pattern";
        end
    else
        debugReport.Status = "completed";
        debugReport.Notes = sprintf('v4 selected grouped candidate %d with text "%s".', ...
            selectedGroupIndex, char(string(plateText)));
    end

    if selectedGroupIndex > 0 && selectedGroupIndex <= numel(candidateGroups)
        chosenGroup = candidateGroups(selectedGroupIndex);
        diagText = sprintf([ ...
            'Selected group %d | RowCount=%d | StructureScore=%.1f | ComponentCount=%d | RowSupport=%d | NormalizedText="%s" | Classification=%s | RejectReason=%s'], ...
            selectedGroupIndex, chosenGroup.RowCount, chosenGroup.StructureScore, ...
            chosenGroup.Support.ComponentCount, chosenGroup.Support.RowSupportOk, ...
            char(classification.CleanedText), classificationToStringV4(classification), rejectionReason);
        debugReport = addDebugStepV4(debugReport, 'Step 13 - Candidate diagnostics', [], diagText);
    end
end

function [grayImage, enhancedImage] = preprocessVehicleImageV4(imageData)
    if ndims(imageData) == 3
        grayImage = rgb2gray(imageData);
    else
        grayImage = imageData;
    end

    grayImage = im2uint8(grayImage);
    grayImage = medfilt2(grayImage, [3 3]);
    enhancedImage = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.018);
    enhancedImage = imsharpen(enhancedImage, 'Radius', 1.1, 'Amount', 0.8);
end

function roiBox = buildSearchROIV4(rows, cols)
    roiLeft = max(1, round(cols * 0.08));
    roiTop = max(1, round(rows * 0.20));
    roiWidth = max(40, round(cols * 0.84));
    roiHeight = max(40, round(rows * 0.68));
    roiBox = clampBoxV4([roiLeft roiTop roiWidth roiHeight], rows, cols);
end

function [componentTable, debugSteps] = detectCharacterComponentsV4(roiImage, roiBox, fullImage)
    [roiRows, roiCols] = size(roiImage);
    roiArea = roiRows * roiCols;
    debugSteps = repmat(makeDebugStepV4("", [], ""), 0, 1);

    darkMask = imbinarize(roiImage, 'adaptive', ...
        'ForegroundPolarity', 'dark', 'Sensitivity', 0.45);
    darkMask = cleanCharacterMaskV4(darkMask, roiRows, roiCols);
    debugSteps(end + 1, 1) = makeDebugStepV4('Step 4 - Dark text mask', darkMask, ...
        'Adaptive dark-text mask used to find character-like blobs.');

    brightMask = imbinarize(roiImage, 'adaptive', ...
        'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
    brightMask = cleanCharacterMaskV4(brightMask, roiRows, roiCols);
    debugSteps(end + 1, 1) = makeDebugStepV4('Step 5 - Bright text mask', brightMask, ...
        'Adaptive bright-text mask to cover inverted or reflective plate styles.');

    mserMask = false(size(roiImage));
    if exist('detectMSERFeatures', 'file') == 2 || exist('detectMSERFeatures', 'builtin') == 5
        try
            areaMin = max(20, round(roiArea * 0.00004));
            areaMax = max(areaMin + 20, round(roiArea * 0.020));
            mserRegions = detectMSERFeatures(roiImage, ...
                'RegionAreaRange', [areaMin areaMax], ...
                'ThresholdDelta', 2);
            for k = 1:mserRegions.Count
                pixelList = round(mserRegions(k).PixelList);
                valid = pixelList(:, 1) >= 1 & pixelList(:, 1) <= roiCols & ...
                    pixelList(:, 2) >= 1 & pixelList(:, 2) <= roiRows;
                pixelList = pixelList(valid, :);
                if isempty(pixelList)
                    continue;
                end
                idx = sub2ind([roiRows roiCols], pixelList(:, 2), pixelList(:, 1));
                mserMask(idx) = true;
            end
            mserMask = cleanCharacterMaskV4(mserMask, roiRows, roiCols);
        catch
            mserMask = false(size(roiImage));
        end
    end
    debugSteps(end + 1, 1) = makeDebugStepV4('Step 6 - MSER mask', mserMask, ...
        'MSER regions added when available to favor stable text blobs over simple rectangles.');

    componentsDark = collectComponentsFromMaskV4(darkMask, roiBox, fullImage, "dark");
    componentsBright = collectComponentsFromMaskV4(brightMask, roiBox, fullImage, "bright");
    componentsMSER = collectComponentsFromMaskV4(mserMask, roiBox, fullImage, "mser");

    componentTable = [componentsDark; componentsBright; componentsMSER];
    if isempty(componentTable)
        return;
    end

    componentTable = deduplicateComponentsV4(componentTable);
    componentTable = componentTable(arrayfun(@(c) isCharacterLikeV4(c, roiRows, roiCols), componentTable));
end

function mask = cleanCharacterMaskV4(mask, rows, cols)
    mask = logical(mask);
    mask = imopen(mask, strel('rectangle', [2 2]));
    mask = imclose(mask, strel('rectangle', [3 3]));
    mask = bwareaopen(mask, max(8, round(rows * cols * 0.00002)));
end

function components = collectComponentsFromMaskV4(mask, roiBox, fullImage, sourceName)
    components = repmat(makeComponentV4([0 0 0 0], sourceName), 0, 1);
    if isempty(mask) || ~any(mask(:))
        return;
    end

    stats = regionprops(mask, 'BoundingBox', 'Area', 'Extent', 'Solidity', ...
        'Eccentricity', 'MajorAxisLength', 'MinorAxisLength', 'Centroid');

    [fullRows, fullCols] = size(fullImage);
    for i = 1:numel(stats)
        bboxROI = stats(i).BoundingBox;
        absBox = [bboxROI(1) + roiBox(1), bboxROI(2) + roiBox(2), bboxROI(3), bboxROI(4)];
        absBox = clampBoxV4(absBox, fullRows, fullCols);

        width = absBox(3);
        height = absBox(4);
        aspectRatio = width / max(height, 1);
        fillRatio = stats(i).Area / max(width * height, 1);
        strokeRatio = stats(i).MajorAxisLength / max(stats(i).MinorAxisLength, 1);

        component = struct( ...
            'Box', absBox, ...
            'Area', stats(i).Area, ...
            'AspectRatio', aspectRatio, ...
            'Extent', stats(i).Extent, ...
            'Solidity', stats(i).Solidity, ...
            'Eccentricity', stats(i).Eccentricity, ...
            'FillRatio', fillRatio, ...
            'StrokeRatio', strokeRatio, ...
            'Center', [stats(i).Centroid(1) + roiBox(1), stats(i).Centroid(2) + roiBox(2)], ...
            'Height', height, ...
            'Width', width, ...
            'Source', string(sourceName));

        components(end + 1, 1) = component; %#ok<AGROW>
    end
end

function component = makeComponentV4(box, sourceName)
    component = struct( ...
        'Box', box, ...
        'Area', 0, ...
        'AspectRatio', 0, ...
        'Extent', 0, ...
        'Solidity', 0, ...
        'Eccentricity', 0, ...
        'FillRatio', 0, ...
        'StrokeRatio', 0, ...
        'Center', [0 0], ...
        'Height', 0, ...
        'Width', 0, ...
        'Source', string(sourceName));
end

function tf = isCharacterLikeV4(component, roiRows, roiCols)
    heightNorm = component.Height / max(roiRows, 1);
    widthNorm = component.Width / max(roiCols, 1);

    tf = true;
    tf = tf && component.Area >= 18;
    tf = tf && heightNorm >= 0.025 && heightNorm <= 0.30;
    tf = tf && widthNorm >= 0.008 && widthNorm <= 0.16;
    tf = tf && component.AspectRatio >= 0.14 && component.AspectRatio <= 1.35;
    tf = tf && component.Extent >= 0.15 && component.Extent <= 0.96;
    tf = tf && component.Solidity >= 0.15;
    tf = tf && component.FillRatio >= 0.12 && component.FillRatio <= 0.92;
    tf = tf && component.StrokeRatio >= 1.0 && component.StrokeRatio <= 14;
end

function components = deduplicateComponentsV4(components)
    if numel(components) < 2
        return;
    end

    keepMask = true(numel(components), 1);
    for i = 1:numel(components)
        if ~keepMask(i)
            continue;
        end
        for j = i + 1:numel(components)
            if ~keepMask(j)
                continue;
            end

            iou = computeIoUV4(components(i).Box, components(j).Box);
            centerDistance = norm(components(i).Center - components(j).Center);
            meanHeight = mean([components(i).Height components(j).Height]);
            if iou > 0.72 || centerDistance < max(4, 0.28 * meanHeight)
                if componentPriorityV4(components(i)) >= componentPriorityV4(components(j))
                    keepMask(j) = false;
                else
                    keepMask(i) = false;
                    break;
                end
            end
        end
    end

    components = components(keepMask);
end

function score = componentPriorityV4(component)
    sourceBonus = 0;
    if component.Source == "mser"
        sourceBonus = 2;
    elseif component.Source == "dark" || component.Source == "bright"
        sourceBonus = 1;
    end

    score = component.Solidity + component.Extent + component.FillRatio + sourceBonus;
end

function groups = groupCharacterComponentsV4(components, roiBox)
    groups = repmat(makeGroupV4([], [0 0 0 0], 0, 1), 0, 1);
    if numel(components) < 2
        return;
    end

    centers = reshape([components.Center], 2, []).';
    heights = [components.Height].';
    [~, order] = sort(centers(:, 1));
    components = components(order);
    centers = centers(order, :);
    heights = heights(order);

    keySet = strings(0, 1);
    rowGroups = repmat(makeGroupV4([], [0 0 0 0], 0, 1), 0, 1);

    for i = 1:numel(components)
        anchorHeight = heights(i);
        anchorY = centers(i, 2);

        compatible = find( ...
            heights >= anchorHeight * 0.55 & heights <= anchorHeight * 1.80 & ...
            abs(centers(:, 2) - anchorY) <= max(10, 0.55 * anchorHeight));

        if numel(compatible) < 2
            continue;
        end

        compatibleComponents = components(compatible);
        compatibleCenters = centers(compatible, :);
        [~, localOrder] = sort(compatibleCenters(:, 1));
        compatible = compatible(localOrder);
        compatibleComponents = compatibleComponents(localOrder);

        segments = splitBySpacingV4(compatibleComponents);
        for s = 1:numel(segments)
            idx = compatible(segments{s});
            if numel(idx) < 2
                continue;
            end

            group = buildGroupFromIndicesV4(components, idx, roiBox, 1);
            if group.Score <= 0
                continue;
            end

            groupKey = compose('%d_', sort(group.ComponentIndices));
            groupKey = strjoin(cellstr(groupKey), '');
            if any(keySet == groupKey)
                continue;
            end
            keySet(end + 1, 1) = string(groupKey); %#ok<AGROW>
            rowGroups(end + 1, 1) = group; %#ok<AGROW>
        end
    end

    groups = rowGroups;
    if isempty(rowGroups)
        return;
    end

    stackedKeys = keySet;
    for i = 1:numel(rowGroups)
        for j = i + 1:numel(rowGroups)
            if ~canFormStackedGroupV4(rowGroups(i), rowGroups(j))
                continue;
            end

            idx = unique([rowGroups(i).ComponentIndices rowGroups(j).ComponentIndices]);
            group = buildGroupFromIndicesV4(components, idx, roiBox, 2);
            if group.Score <= 0
                continue;
            end

            groupKey = compose('%d_', sort(group.ComponentIndices));
            groupKey = strjoin(cellstr(groupKey), '');
            if any(stackedKeys == groupKey)
                continue;
            end
            stackedKeys(end + 1, 1) = string(groupKey); %#ok<AGROW>
            groups(end + 1, 1) = group; %#ok<AGROW>
        end
    end
end

function segments = splitBySpacingV4(components)
    segments = {};
    if isempty(components)
        return;
    end

    x1 = arrayfun(@(c) c.Box(1), components);
    x2 = arrayfun(@(c) c.Box(1) + c.Box(3), components);
    heights = arrayfun(@(c) c.Height, components);
    meanHeight = max(8, median(heights));
    maxGap = max(16, 1.9 * meanHeight);

    currentSegment = 1;
    for i = 2:numel(components)
        gap = x1(i) - x2(i - 1);
        if gap > maxGap
            segments{end + 1} = currentSegment:(i - 1); %#ok<AGROW>
            currentSegment = i;
        end
    end
    segments{end + 1} = currentSegment:numel(components);
end

function tf = canFormStackedGroupV4(groupA, groupB)
    boxA = groupA.Box;
    boxB = groupB.Box;
    centerAX = boxA(1) + boxA(3) / 2;
    centerBX = boxB(1) + boxB(3) / 2;
    xOverlap = overlapAmountV4([boxA(1), boxA(1) + boxA(3)], [boxB(1), boxB(1) + boxB(3)]);
    minWidth = max(1, min(boxA(3), boxB(3)));
    verticalGap = abs((boxA(2) + boxA(4) / 2) - (boxB(2) + boxB(4) / 2));
    meanHeight = mean([boxA(4) boxB(4)]);

    tf = abs(centerAX - centerBX) <= max(18, 0.22 * max(boxA(3), boxB(3))) && ...
        xOverlap / minWidth >= 0.45 && ...
        verticalGap <= 2.4 * meanHeight;
end

function group = buildGroupFromIndicesV4(components, indices, roiBox, rowCount)
    componentSubset = components(indices);
    boxes = vertcat(componentSubset.Box);
    unionBox = unionBoxesV4(boxes);
    expandedBox = expandBoundingBoxV4(unionBox, roiBox, rowCount);
    score = scoreCharacterGroupV4(componentSubset, expandedBox, roiBox, rowCount);

    group = struct( ...
        'ComponentIndices', indices, ...
        'Box', expandedBox, ...
        'Score', score, ...
        'RowCount', rowCount);
end

function group = makeGroupV4(indices, box, score, rowCount)
    group = struct( ...
        'ComponentIndices', indices, ...
        'Box', box, ...
        'Score', score, ...
        'RowCount', rowCount);
end

function expandedBox = expandBoundingBoxV4(box, roiBox, rowCount)
    marginX = max(10, round(box(3) * 0.18));
    marginY = max(6, round(box(4) * 0.30));
    if rowCount == 2
        marginY = max(marginY, round(box(4) * 0.14));
    end

    fullRows = roiBox(2) + roiBox(4) + 4;
    fullCols = roiBox(1) + roiBox(3) + 4;
    expandedBox = clampBoxV4([box(1) - marginX, box(2) - marginY, ...
        box(3) + 2 * marginX, box(4) + 2 * marginY], fullRows, fullCols);
end

function score = scoreCharacterGroupV4(components, candidateBox, roiBox, rowCount)
    count = numel(components);
    if count < 2
        score = -inf;
        return;
    end

    heights = [components.Height];
    centers = reshape([components.Center], 2, []).';
    widths = [components.Width];

    [xCenters, sortOrder] = sort(centers(:, 1));
    yCenters = centers(sortOrder, 2);
    heights = heights(sortOrder);
    widths = widths(sortOrder);

    if count > 1
        gaps = diff(xCenters) - widths(1:end - 1) / 2 - widths(2:end) / 2;
    else
        gaps = 0;
    end

    meanHeight = max(1, mean(heights));
    heightConsistency = 1 - min(std(double(heights)) / meanHeight, 1);
    alignmentConsistency = 1 - min(std(double(yCenters)) / meanHeight, 1);
    if isempty(gaps)
        gapConsistency = 0.4;
    else
        gapConsistency = 1 - min(std(double(gaps)) / max(6, mean(abs(gaps)) + 1), 1);
    end

    aspectRatio = candidateBox(3) / max(candidateBox(4), 1);
    if rowCount == 1
        if aspectRatio < 1.4
            score = -inf;
            return;
        end
        aspectScore = 1 - min(abs(aspectRatio - 3.2) / 3.0, 1);
    else
        if aspectRatio < 0.45 || aspectRatio > 1.9
            score = -inf;
            return;
        end
        aspectScore = 1 - min(abs(aspectRatio - 1.6) / 1.6, 1);
    end

    roiCenter = [roiBox(1) + roiBox(3) / 2, roiBox(2) + roiBox(4) / 2];
    candidateCenter = [candidateBox(1) + candidateBox(3) / 2, candidateBox(2) + candidateBox(4) / 2];
    xCenterPenalty = abs(candidateCenter(1) - roiCenter(1)) / max(roiBox(3) / 2, 1);
    yPreferred = roiBox(2) + roiBox(4) * 0.62;
    yCenterPenalty = abs(candidateCenter(2) - yPreferred) / max(roiBox(4) / 2, 1);
    centeredness = 1 - min(0.55 * xCenterPenalty + 0.45 * yCenterPenalty, 1);

    compactness = min((count * meanHeight) / max(candidateBox(3), 1), 1);
    rectangularity = min((candidateBox(3) * candidateBox(4)) / max(sum(widths .* heights), 1), 4);
    rectangularity = 1 - min(abs(rectangularity - 2.0) / 2.5, 1);

    minimumCount = 2;
    if rowCount == 1
        minimumCount = 3;
    end
    if count < minimumCount
        score = -inf;
        return;
    end

    score = 18 * count + ...
        24 * heightConsistency + ...
        24 * alignmentConsistency + ...
        18 * gapConsistency + ...
        14 * aspectScore + ...
        12 * centeredness + ...
        10 * compactness + ...
        8 * rectangularity;
end

function [bestText, bestScore, bestCrop, bestBinary, variantStrip, variantNote, sanityPass] = runOCROnGroupedCandidateV4(grayImage, candidateGroup, roiBox, allowNormalization)
    bestText = "";
    bestScore = -inf;
    bestCrop = [];
    bestBinary = [];
    variantStrip = [];
    variantNote = "";
    sanityPass = false;

    [rows, cols] = size(grayImage);
    candidateBox = clampBoxV4(candidateGroup.Box, rows, cols);
    cropGray = imcrop(grayImage, candidateBox);
    if isempty(cropGray)
        return;
    end

    cropGray = im2uint8(cropGray);
    cropGray = trimCandidateBordersV4(cropGray);
    bestCrop = cropGray;

    scaleOptions = [2 3];
    if min(size(cropGray)) < 28
        scaleOptions = [2 3 4];
    end

    variantImages = cell(0, 1);
    variantLabels = strings(0, 1);

    for scale = scaleOptions
        scaled = imresize(cropGray, scale, 'bicubic');
        enhanced = adapthisteq(scaled, ...
            'NumTiles', [max(2, min(8, floor(size(scaled, 1) / 18))), ...
            max(2, min(8, floor(size(scaled, 2) / 18)))], ...
            'ClipLimit', 0.02);
        enhanced = imsharpen(enhanced, 'Radius', 0.9, 'Amount', 0.9);

        darkBinary = imbinarize(enhanced, 'adaptive', ...
            'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
        brightBinary = imbinarize(enhanced, 'adaptive', ...
            'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
        darkBinary = cleanOCRMaskV4(darkBinary);
        brightBinary = cleanOCRMaskV4(brightBinary);

        variantImages{end + 1} = enhanced; %#ok<AGROW>
        variantLabels(end + 1, 1) = sprintf('gray_%dx', scale); %#ok<AGROW>

        variantImages{end + 1} = darkBinary; %#ok<AGROW>
        variantLabels(end + 1, 1) = sprintf('darkbin_%dx', scale); %#ok<AGROW>

        variantImages{end + 1} = ~darkBinary; %#ok<AGROW>
        variantLabels(end + 1, 1) = sprintf('darkinv_%dx', scale); %#ok<AGROW>

        variantImages{end + 1} = brightBinary; %#ok<AGROW>
        variantLabels(end + 1, 1) = sprintf('brightbin_%dx', scale); %#ok<AGROW>
    end

    if isempty(variantImages)
        return;
    end

    variantStrip = makeVariantStripV4(variantImages(1:min(6, numel(variantImages))));
    variantNote = sprintf('OCR variants tested: %s', strjoin(cellstr(variantLabels(1:min(6, numel(variantLabels)))), ', '));

    stackedHint = isStackedCandidateV4(candidateBox);
    if stackedHint && candidateGroup.RowCount == 1
        candidateGroup.RowCount = 2;
    end

    for i = 1:numel(variantImages)
        currentVariant = variantImages{i};
        [recognizedText, ocrConfidence, sanityOk] = performOCRV4(currentVariant, candidateGroup.RowCount, allowNormalization);
        ocrScore = scoreOCRTextV4(recognizedText, ocrConfidence, candidateBox, size(grayImage), roiBox, candidateGroup.RowCount);
        if sanityOk
            ocrScore = ocrScore + 18;
        else
            ocrScore = ocrScore - 22;
        end

        if ocrScore > bestScore
            bestScore = ocrScore;
            bestText = recognizedText;
            bestBinary = currentVariant;
            sanityPass = sanityOk;
        end
    end

    if stackedHint
        [stackedText, stackedConfidence, stackedOk] = runExplicitTwoLineOCRV4(cropGray, allowNormalization);
        stackedScore = scoreOCRTextV4(stackedText, stackedConfidence, candidateBox, size(grayImage), roiBox, 2);
        if stackedOk
            stackedScore = stackedScore + 25;
        else
            stackedScore = stackedScore - 10;
        end
        if stackedScore > bestScore
            bestScore = stackedScore;
            bestText = stackedText;
            bestBinary = cropGray;
            sanityPass = stackedOk;
        end
    end
end

function trimmed = trimCandidateBordersV4(cropGray)
    trimmed = cropGray;
    if isempty(cropGray)
        return;
    end

    trimY = max(1, round(size(cropGray, 1) * 0.03));
    trimX = max(1, round(size(cropGray, 2) * 0.02));
    if size(cropGray, 1) > 2 * trimY && size(cropGray, 2) > 2 * trimX
        trimmed = cropGray((1 + trimY):(end - trimY), (1 + trimX):(end - trimX));
    end
end

function mask = cleanOCRMaskV4(mask)
    mask = logical(mask);
    mask = imopen(mask, strel('rectangle', [2 2]));
    mask = imclose(mask, strel('rectangle', [3 2]));
    mask = bwareaopen(mask, 12);
end

function [plateText, confidence, sanityOk] = performOCRV4(ocrInput, rowCount, allowNormalization)
    ocrInput = makeOCRReadyImageV4(ocrInput);
    textLayout = 'Word';
    if rowCount == 2
        textLayout = 'Block';
    end

    plateText = "";
    confidence = 0;
    sanityOk = false;

    [baseText, baseConfidence] = runRawOCRV4(ocrInput, textLayout);
    plateText = sanitizeOCRTextV4(baseText);
    confidence = baseConfidence;

    if rowCount == 2
        [twoLineText, twoLineConfidence] = performTwoLineOCRV4(ocrInput, allowNormalization);
        if scoreSanitizedTextV4(twoLineText, twoLineConfidence) > scoreSanitizedTextV4(plateText, confidence)
            plateText = twoLineText;
            confidence = twoLineConfidence;
        end
    end

    if allowNormalization
        [plateText, confidence] = pickBestNormalizedReadV4(plateText, confidence);
    end

    sanityOk = passesCropSanityV4(ocrInput, rowCount);
end

function [plateText, confidence] = performTwoLineOCRV4(ocrInput, allowNormalization)
    plateText = "";
    confidence = 0;

    splitRow = max(2, round(size(ocrInput, 1) / 2));
    topHalf = ocrInput(1:splitRow, :);
    bottomHalf = ocrInput(splitRow:end, :);

    [topText, topConfidence] = runRawOCRV4(topHalf, 'Word');
    [bottomText, bottomConfidence] = runRawOCRV4(bottomHalf, 'Word');

    combinedText = sanitizeOCRTextV4(append(string(topText), string(bottomText)));
    combinedConfidence = mean([topConfidence bottomConfidence]);
    if strlength(combinedText) > 0
        plateText = combinedText;
        confidence = combinedConfidence;
    end

    if allowNormalization && strlength(plateText) > 0
        [plateText, confidence] = pickBestNormalizedReadV4(plateText, confidence);
    end
end

function score = scoreOCRTextV4(plateText, confidence, candidateBox, imageSize, roiBox, rowCount)
    cleanedText = sanitizeOCRTextV4(plateText);
    score = scoreSanitizedTextV4(cleanedText, confidence);

    if strlength(cleanedText) == 0
        score = score - 70;
        return;
    end

    classification = classifyMalaysianPlateReadV4(cleanedText);
    if classification.IsStrongValid
        if confidence < 12 && strlength(cleanedText) <= 4
            score = score + 28;
        else
            score = score + 125;
        end
    elseif classification.IsPlausiblePartial
        score = score + 22;
    else
        score = score - 60;
    end

    alphaCount = sum(isstrprop(char(cleanedText), 'alpha'));
    digitCount = sum(isstrprop(char(cleanedText), 'digit'));
    if digitCount == 0 && alphaCount >= 3
        score = score - 40;
    elseif alphaCount > max(1, digitCount) * 2 && ~classification.IsStrongValid
        score = score - 25;
    end

    aspectRatio = candidateBox(3) / max(candidateBox(4), 1);
    if rowCount == 1
        score = score + max(0, 16 - abs(aspectRatio - 3.1) * 8);
    else
        score = score + max(0, 16 - abs(aspectRatio - 1.7) * 10);
    end

    candidateCenter = [candidateBox(1) + candidateBox(3) / 2, candidateBox(2) + candidateBox(4) / 2];
    roiCenter = [roiBox(1) + roiBox(3) / 2, roiBox(2) + roiBox(4) * 0.62];
    distanceScore = 1 - min(norm(candidateCenter - roiCenter) / norm([roiBox(3) roiBox(4)]), 1);
    score = score + 12 * distanceScore;

    imageRows = imageSize(1);
    imageCols = imageSize(2);
    if candidateBox(3) > imageCols * 0.55 || candidateBox(4) > imageRows * 0.24
        score = score - 18;
    end
end

function score = scoreSanitizedTextV4(cleanedText, confidence)
    score = max(0, double(strlength(cleanedText)) * 8);

    if any(isstrprop(char(cleanedText), 'alpha'))
        score = score + 8;
    end
    if any(isstrprop(char(cleanedText), 'digit'))
        score = score + 8;
    end

    score = score + max(0, min(30, confidence / 3));
end

function [bestText, bestConfidence] = pickBestNormalizedReadV4(textValue, confidence)
    bestText = sanitizeOCRTextV4(textValue);
    bestConfidence = confidence;
    bestScore = -inf;

    variants = generateNormalizedVariantsV4(bestText);
    for i = 1:numel(variants)
        currentText = variants{i};
        classification = classifyMalaysianPlateReadV4(currentText);
        score = scoreSanitizedTextV4(currentText, confidence) + classificationScoreV4(classification);
        if score > bestScore
            bestScore = score;
            bestText = currentText;
            bestConfidence = confidence;
        end
    end
end

function variants = generateNormalizedVariantsV4(textValue)
    baseText = sanitizeOCRTextV4(textValue);
    variants = {char(baseText)};

    replacements = {
        '0', 'O'
        'O', '0'
        '1', 'I'
        'I', '1'
        '8', 'B'
        'B', '8'
        '5', 'S'
        'S', '5'
        '2', 'Z'
        'Z', '2'
    };

    for i = 1:size(replacements, 1)
        fromChar = replacements{i, 1};
        toChar = replacements{i, 2};
        altText = replace(string(baseText), fromChar, toChar);
        if altText ~= baseText
            variants{end + 1} = char(altText); %#ok<AGROW>
        end
    end

    variants = unique(variants);
end

function classification = classifyMalaysianPlateReadV4(textValue)
    cleanedText = sanitizeOCRTextV4(textValue);
    classification = struct( ...
        'IsStrongValid', false, ...
        'IsPlausiblePartial', false, ...
        'IsReject', false, ...
        'CleanedText', cleanedText);

    if strlength(cleanedText) < 1 || strlength(cleanedText) > 10
        classification.IsReject = true;
        return;
    end

    standardPattern = '^[A-Z]{1,3}\d{1,4}[A-Z]{0,2}$';
    shortPattern = '^[A-Z]\d{1,4}$';
    stackedPattern = '^[A-Z]{1,4}\d{1,4}$';
    mixedPattern = '^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$';

    if ~isempty(regexp(char(cleanedText), standardPattern, 'once')) || ...
            ~isempty(regexp(char(cleanedText), shortPattern, 'once')) || ...
            ~isempty(regexp(char(cleanedText), stackedPattern, 'once')) || ...
            ~isempty(regexp(char(cleanedText), mixedPattern, 'once'))
        classification.IsStrongValid = true;
        return;
    end

    hasAlpha = any(isstrprop(char(cleanedText), 'alpha'));
    hasDigit = any(isstrprop(char(cleanedText), 'digit'));
    if hasAlpha || hasDigit
        if strlength(cleanedText) <= 4
            classification.IsPlausiblePartial = true;
            return;
        end
    end

    classification.IsReject = true;
end

function score = classificationScoreV4(classification)
    if classification.IsStrongValid
        score = 120;
        return;
    end
    if classification.IsPlausiblePartial
        score = 18;
        return;
    end
    score = -60;
end

function label = classificationToStringV4(classification)
    if classification.IsStrongValid
        label = "strong-valid";
    elseif classification.IsPlausiblePartial
        label = "plausible-partial";
    else
        label = "reject";
    end
end

function [rawText, confidence] = runRawOCRV4(ocrInput, textLayout)
    rawText = "";
    confidence = 0;

    try
        result = ocr(ocrInput, ...
            'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789', ...
            'TextLayout', textLayout);
    catch
        try
            result = ocr(ocrInput, ...
                'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789');
        catch
            try
                result = ocr(ocrInput);
            catch
                result = [];
            end
        end
    end

    if isempty(result)
        return;
    end

    rawText = string(result.Text);
    try
        wordConfidences = result.WordConfidences;
    catch
        wordConfidences = [];
    end
    if ~isempty(wordConfidences)
        valid = ~isnan(wordConfidences);
        if any(valid)
            confidence = mean(double(wordConfidences(valid)));
        end
    end
end

function sanityOk = passesCropSanityV4(cropInput, rowCount)
    sanityOk = false;
    if isempty(cropInput)
        return;
    end

    cropInput = makeOCRReadyImageV4(cropInput);
    if size(cropInput, 1) < 16 || size(cropInput, 2) < 32
        return;
    end

    contrastValue = std2(cropInput);
    if contrastValue < 12
        return;
    end

    [gx, gy] = imgradientxy(cropInput, 'sobel');
    if mean(abs(gx), 'all') + mean(abs(gy), 'all') < 8
        return;
    end

    darkMask = imbinarize(cropInput, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.45);
    brightMask = imbinarize(cropInput, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
    binaryMask = cleanOCRMaskV4(darkMask | brightMask);

    fgRatio = nnz(binaryMask) / numel(binaryMask);
    if fgRatio < 0.02 || fgRatio > 0.65
        return;
    end

    [componentCount, rowSupportOk] = countCharacterLikeComponentsInMaskV4(binaryMask, rowCount);
    if componentCount < 3 || ~rowSupportOk
        return;
    end

    stats = regionprops(binaryMask, 'BoundingBox', 'Centroid');
    if isempty(stats)
        return;
    end
    boxes = reshape([stats.BoundingBox], 4, []).';
    unionBox = unionBoxesV4(boxes);
    coverage = (unionBox(3) * unionBox(4)) / numel(binaryMask);
    if coverage < 0.15
        return;
    end

    centroid = mean(reshape([stats.Centroid], 2, []).', 1);
    xNorm = centroid(1) / size(binaryMask, 2);
    yNorm = centroid(2) / size(binaryMask, 1);
    if (xNorm < 0.18 || xNorm > 0.82) && (yNorm < 0.18 || yNorm > 0.82)
        return;
    end

    sanityOk = true;
end

function [componentCount, rowSupportOk] = countCharacterLikeComponentsInMaskV4(binaryMask, rowCount)
    componentCount = 0;
    rowSupportOk = false;

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
    boxes = boxes(keep, :);
    if isempty(boxes)
        return;
    end

    componentCount = size(boxes, 1);
    if rowCount == 1
        rowSupportOk = componentCount >= 3;
        return;
    end

    midY = size(binaryMask, 1) / 2;
    centersY = boxes(:, 2) + boxes(:, 4) / 2;
    upperCount = sum(centersY <= midY);
    lowerCount = sum(centersY > midY);
    rowSupportOk = upperCount >= 2 && lowerCount >= 1;
end

function tf = isStackedCandidateV4(candidateBox)
    aspectRatio = candidateBox(3) / max(candidateBox(4), 1);
    tf = aspectRatio >= 0.45 && aspectRatio <= 1.4;
end

function [combinedText, confidence, sanityOk] = runExplicitTwoLineOCRV4(cropGray, allowNormalization)
    combinedText = "";
    confidence = 0;
    sanityOk = false;
    if isempty(cropGray)
        return;
    end

    cropGray = im2uint8(cropGray);
    binaryMask = imbinarize(cropGray, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.45);
    binaryMask = cleanOCRMaskV4(binaryMask);
    stats = regionprops(binaryMask, 'BoundingBox', 'Centroid');
    if numel(stats) < 3
        return;
    end

    centersY = reshape([stats.Centroid], 2, []).';
    centersY = centersY(:, 2);
    [~, order] = sort(centersY);
    centersY = centersY(order);
    splitIndex = max(1, round(numel(centersY) / 2));
    upperMean = mean(centersY(1:splitIndex));
    lowerMean = mean(centersY(splitIndex + 1:end));
    if lowerMean - upperMean < size(cropGray, 1) * 0.18
        return;
    end

    splitRow = round((upperMean + lowerMean) / 2);
    splitRow = max(2, min(size(cropGray, 1) - 2, splitRow));
    topHalf = cropGray(1:splitRow, :);
    bottomHalf = cropGray(splitRow:end, :);

    [topText, topConfidence] = runRawOCRV4(topHalf, 'Word');
    [bottomText, bottomConfidence] = runRawOCRV4(bottomHalf, 'Word');
    combinedText = sanitizeOCRTextV4(string(topText) + string(bottomText));
    confidence = mean([topConfidence bottomConfidence]);
    if allowNormalization
        [combinedText, confidence] = pickBestNormalizedReadV4(combinedText, confidence);
    end
    sanityOk = passesCropSanityV4(cropGray, 2);
end

function [structureScore, supportInfo] = scoreCandidateStructureV4(enhancedImage, candidateBox, componentTable, roiBox, rowCount)
    structureScore = 0;
    supportInfo = struct('ComponentCount', 0, 'FgRatio', 0, 'RowSupportOk', false);

    roiArea = roiBox(3) * roiBox(4);
    candidateArea = candidateBox(3) * candidateBox(4);
    if candidateBox(3) > roiBox(3) * 0.55 || candidateArea > roiArea * 0.18
        structureScore = structureScore - 140;
    elseif candidateArea > roiArea * 0.30
        structureScore = structureScore - 60;
    end
    if rowCount == 1 && candidateBox(4) > roiBox(4) * 0.35
        structureScore = structureScore - 120;
    end
    if rowCount == 2 && candidateBox(4) > roiBox(4) * 0.50
        structureScore = structureScore - 120;
    end

    roiCenter = [roiBox(1) + roiBox(3) / 2, roiBox(2) + roiBox(4) / 2];
    candidateCenter = [candidateBox(1) + candidateBox(3) / 2, candidateBox(2) + candidateBox(4) / 2];
    xCenterPenalty = abs(candidateCenter(1) - roiCenter(1)) / max(roiBox(3) / 2, 1);
    yPreferred = roiBox(2) + roiBox(4) * 0.62;
    yPenalty = abs(candidateCenter(2) - yPreferred) / max(roiBox(4) / 2, 1);
    centeredness = 1 - min(0.6 * xCenterPenalty + 0.4 * yPenalty, 1);
    structureScore = structureScore + 42 * centeredness;

    yNorm = (candidateCenter(2) - roiBox(2)) / max(roiBox(4), 1);
    if yNorm < 0.35
        structureScore = structureScore - 55;
    elseif yNorm > 0.90
        structureScore = structureScore - 25;
    end

    crop = imcrop(enhancedImage, candidateBox);
    if isempty(crop)
        structureScore = structureScore - 120;
        return;
    end

    darkMask = imbinarize(crop, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.45);
    brightMask = imbinarize(crop, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
    binaryMask = cleanOCRMaskV4(darkMask | brightMask);
    fgRatio = nnz(binaryMask) / numel(binaryMask);
    supportInfo.FgRatio = fgRatio;

    if fgRatio < 0.02 || fgRatio > 0.65
        structureScore = structureScore - 55;
    else
        fgScore = 1 - min(abs(fgRatio - 0.22) / 0.22, 1);
        structureScore = structureScore + 26 * fgScore;
    end

    if candidateBox(3) / max(candidateBox(4), 1) > 4.8 && fgRatio < 0.06
        structureScore = structureScore - 25;
    end

    [gx, gy] = imgradientxy(crop, 'sobel');
    edgeDensity = mean(abs(gx) > 40, 'all');
    if mean(abs(gx), 'all') > 1.4 * mean(abs(gy), 'all') && edgeDensity > 0.12
        structureScore = structureScore - 24;
    end

    blankRatio = 1 - fgRatio;
    if blankRatio > 0.88
        structureScore = structureScore - 45;
    end

    inBox = arrayfun(@(c) isCenterInsideBoxV4(c.Center, candidateBox), componentTable);
    componentsInside = componentTable(inBox);
    supportInfo.ComponentCount = numel(componentsInside);
    if isempty(componentsInside)
        structureScore = structureScore - 90;
        return;
    end

    heights = [componentsInside.Height];
    widths = [componentsInside.Width];
    centers = reshape([componentsInside.Center], 2, []).';
    heightConsistency = 1 - min(std(double(heights)) / max(mean(heights), 1), 1);
    widthConsistency = 1 - min(std(double(widths)) / max(mean(widths), 1), 1);
    alignmentConsistency = 1 - min(std(double(centers(:, 2))) / max(mean(heights), 1), 1);
    spacingConsistency = 0.6;
    if size(centers, 1) > 2
        [sortedX, order] = sort(centers(:, 1));
        sortedWidths = widths(order);
        gaps = diff(sortedX) - (sortedWidths(1:end - 1) / 2 + sortedWidths(2:end) / 2);
        spacingConsistency = 1 - min(std(double(gaps)) / max(mean(abs(gaps)) + 1, 1), 1);
    end
    structureScore = structureScore + 18 * heightConsistency + 12 * widthConsistency + 18 * alignmentConsistency;
    structureScore = structureScore + 14 * spacingConsistency;

    rowSupportOk = false;
    if rowCount == 1
        rowSupportOk = numel(componentsInside) >= 3;
    else
        midY = candidateBox(2) + candidateBox(4) / 2;
        upperCount = sum(centers(:, 2) <= midY);
        lowerCount = sum(centers(:, 2) > midY);
        rowSupportOk = upperCount >= 2 && lowerCount >= 1;
    end
    supportInfo.RowSupportOk = rowSupportOk;
    if ~rowSupportOk
        structureScore = structureScore - 70;
    else
        structureScore = structureScore + 28;
    end

    if ~rowSupportOk && yNorm < 0.5
        structureScore = structureScore - 24;
    end
end

function tf = isCenterInsideBoxV4(centerPoint, box)
    tf = centerPoint(1) >= box(1) && centerPoint(1) <= box(1) + box(3) && ...
        centerPoint(2) >= box(2) && centerPoint(2) <= box(2) + box(4);
end

function cleanedText = sanitizeOCRTextV4(textValue)
    cleanedText = upper(string(textValue));
    cleanedText = regexprep(cleanedText, '[^A-Z0-9]', '');
    if strlength(cleanedText) > 10
        cleanedText = extractBefore(cleanedText, 11);
    end
end

function tf = isApprovedMalaysiaPlateV4(textValue)
    cleanedText = sanitizeOCRTextV4(textValue);
    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        tf = false;
        return;
    end

    standardPattern = '^[A-Z]{1,3}\d{1,4}[A-Z]{0,2}$';
    shortPattern = '^[A-Z]\d{1,4}$';
    diplomaticPattern = '^[A-Z]{1,2}\d{1,4}[A-Z]{1,3}$';

    tf = ~isempty(regexp(char(cleanedText), standardPattern, 'once')) || ...
        ~isempty(regexp(char(cleanedText), shortPattern, 'once')) || ...
        ~isempty(regexp(char(cleanedText), diplomaticPattern, 'once'));
end

function tf = isWeakButUsablePlateV4(textValue)
    cleanedText = sanitizeOCRTextV4(textValue);
    if strlength(cleanedText) < 2 || strlength(cleanedText) > 10
        tf = false;
        return;
    end

    hasAlpha = any(isstrprop(char(cleanedText), 'alpha'));
    hasDigit = any(isstrprop(char(cleanedText), 'digit'));
    tf = hasAlpha && hasDigit;
end

function imageData = makeOCRReadyImageV4(imageData)
    if islogical(imageData)
        imageData = uint8(imageData) * 255;
    elseif isfloat(imageData)
        imageData = im2uint8(mat2gray(imageData));
    else
        imageData = im2uint8(imageData);
    end
end

function stripImage = makeVariantStripV4(imageList)
    if isempty(imageList)
        stripImage = [];
        return;
    end

    targetHeight = 110;
    prepared = cell(size(imageList));
    totalWidth = 10;
    for i = 1:numel(imageList)
        currentImage = makeOCRReadyImageV4(imageList{i});
        if ndims(currentImage) == 2
            currentImage = repmat(currentImage, 1, 1, 3);
        end
        scale = targetHeight / max(size(currentImage, 1), 1);
        resized = imresize(currentImage, scale);
        prepared{i} = resized;
        totalWidth = totalWidth + size(resized, 2) + 10;
    end

    stripImage = uint8(255 * ones(targetHeight + 20, totalWidth, 3));
    currentX = 11;
    for i = 1:numel(prepared)
        currentImage = prepared{i};
        h = size(currentImage, 1);
        w = size(currentImage, 2);
        y = floor((size(stripImage, 1) - h) / 2) + 1;
        stripImage(y:(y + h - 1), currentX:(currentX + w - 1), :) = currentImage;
        currentX = currentX + w + 10;
    end
end

function overlayImage = overlayBoxesOnImageV4(imageData, candidateBoxes, rgbColor)
    if isempty(imageData)
        overlayImage = [];
        return;
    end

    if ndims(imageData) == 2
        overlayImage = repmat(im2uint8(imageData), 1, 1, 3);
    else
        overlayImage = im2uint8(imageData);
    end

    if isempty(candidateBoxes)
        return;
    end

    overlayImage = insertShape(overlayImage, 'Rectangle', candidateBoxes, ...
        'Color', rgbColor, 'LineWidth', 3);
end

function debugReport = initDebugReportV4(imageData)
    debugReport = struct( ...
        'Method', "v4", ...
        'Status', "running", ...
        'Notes', "", ...
        'Steps', repmat(makeDebugStepV4("", [], ""), 0, 1));
    debugReport = addDebugStepV4(debugReport, 'Input image', imageData, ...
        'Original image passed into v4 grouped-text detector.');
end

function debugReport = addDebugStepV4(debugReport, titleText, imageData, descriptionText)
    debugReport.Steps(end + 1, 1) = makeDebugStepV4(titleText, imageData, descriptionText);
end

function debugReport = appendDebugStepsV4(debugReport, steps)
    if isempty(steps)
        return;
    end
    debugReport.Steps = [debugReport.Steps; steps];
end

function step = makeDebugStepV4(titleText, imageData, descriptionText)
    step = struct( ...
        'Title', string(titleText), ...
        'Image', imageData, ...
        'Description', string(descriptionText));
end

function box = clampBoxV4(box, rows, cols)
    box = round(double(box));
    x = min(max(1, box(1)), cols);
    y = min(max(1, box(2)), rows);
    w = max(1, box(3));
    h = max(1, box(4));

    if x + w - 1 > cols
        w = cols - x + 1;
    end
    if y + h - 1 > rows
        h = rows - y + 1;
    end

    box = [x y w h];
end

function unionBox = unionBoxesV4(boxes)
    x1 = min(boxes(:, 1));
    y1 = min(boxes(:, 2));
    x2 = max(boxes(:, 1) + boxes(:, 3));
    y2 = max(boxes(:, 2) + boxes(:, 4));
    unionBox = [x1 y1 x2 - x1 y2 - y1];
end

function iou = computeIoUV4(boxA, boxB)
    x1 = max(boxA(1), boxB(1));
    y1 = max(boxA(2), boxB(2));
    x2 = min(boxA(1) + boxA(3), boxB(1) + boxB(3));
    y2 = min(boxA(2) + boxA(4), boxB(2) + boxB(4));

    interWidth = max(0, x2 - x1);
    interHeight = max(0, y2 - y1);
    intersection = interWidth * interHeight;
    unionArea = boxA(3) * boxA(4) + boxB(3) * boxB(4) - intersection;
    iou = intersection / max(unionArea, 1);
end

function overlap = overlapAmountV4(intervalA, intervalB)
    overlap = max(0, min(intervalA(2), intervalB(2)) - max(intervalA(1), intervalB(1)));
end
