function OCRPlateTesterUI
%OCRPLATETESTERUI Manual OCR tester for license plate crops.
% Lets you upload an image, draw/select the plate ROI, preview several
% OCR-ready variants, and compare the extracted text.

    app = struct();
    app.Image = [];
    app.ImagePath = "";
    app.ROI = [];
    app.ROIHandle = [];

    screenSize = get(groot, 'ScreenSize');
    figWidth = min(1500, screenSize(3) - 80);
    figHeight = min(920, screenSize(4) - 80);
    figLeft = max(30, floor((screenSize(3) - figWidth) / 2));
    figBottom = max(30, floor((screenSize(4) - figHeight) / 2));

    app.Figure = uifigure( ...
        'Name', 'Plate OCR Tester', ...
        'Position', [figLeft figBottom figWidth figHeight], ...
        'Color', [0.96 0.97 0.99]);

    app.MainPanel = uipanel(app.Figure, ...
        'Position', [0 0 figWidth figHeight], ...
        'BorderType', 'none', ...
        'BackgroundColor', [0.96 0.97 0.99], ...
        'Scrollable', 'on');

    contentWidth = figWidth - 30;
    contentHeight = 1280;

    app.Header = uipanel(app.MainPanel, ...
        'Position', [15 contentHeight - 150 contentWidth 130], ...
        'BackgroundColor', [0.99 0.99 1.00], ...
        'BorderType', 'line');

    uilabel(app.Header, ...
        'Position', [22 72 420 36], ...
        'Text', 'Plate OCR Tester', ...
        'FontSize', 28, ...
        'FontWeight', 'bold', ...
        'FontColor', [0.10 0.16 0.24]);

    uilabel(app.Header, ...
        'Position', [22 42 900 24], ...
        'Text', 'Upload an image, draw the exact plate box manually, then compare OCR on multiple preprocessing variants.', ...
        'FontSize', 13, ...
        'FontColor', [0.35 0.40 0.48]);

    app.UploadButton = uibutton(app.Header, 'push', ...
        'Text', 'Upload Image', ...
        'Position', [22 10 140 30], ...
        'ButtonPushedFcn', @onUploadImage, ...
        'BackgroundColor', [0.19 0.43 0.82], ...
        'FontColor', [1 1 1], ...
        'FontWeight', 'bold');

    app.SelectROIButton = uibutton(app.Header, 'push', ...
        'Text', 'Draw ROI', ...
        'Position', [176 10 120 30], ...
        'ButtonPushedFcn', @onDrawROI, ...
        'Enable', 'off', ...
        'BackgroundColor', [0.17 0.62 0.34], ...
        'FontColor', [1 1 1], ...
        'FontWeight', 'bold');

    app.RunOCRButton = uibutton(app.Header, 'push', ...
        'Text', 'Run OCR', ...
        'Position', [310 10 120 30], ...
        'ButtonPushedFcn', @onRunOCR, ...
        'Enable', 'off', ...
        'BackgroundColor', [0.89 0.54 0.05], ...
        'FontColor', [1 1 1], ...
        'FontWeight', 'bold');

    app.AutoDetectButton = uibutton(app.Header, 'push', ...
        'Text', 'Auto Crop', ...
        'Position', [444 10 120 30], ...
        'ButtonPushedFcn', @onAutoCrop, ...
        'Enable', 'off');

    app.ClearButton = uibutton(app.Header, 'push', ...
        'Text', 'Clear', ...
        'Position', [578 10 100 30], ...
        'ButtonPushedFcn', @onClear);

    app.PathLabel = uilabel(app.MainPanel, ...
        'Position', [24 contentHeight - 182 contentWidth - 48 24], ...
        'Text', 'Selected image: none', ...
        'FontSize', 12, ...
        'FontColor', [0.28 0.31 0.36]);

    app.StatusLabel = uilabel(app.MainPanel, ...
        'Position', [24 contentHeight - 210 contentWidth - 48 24], ...
        'Text', 'Status: upload an image to begin', ...
        'FontSize', 12, ...
        'FontColor', [0.38 0.42 0.48]);

    leftWidth = floor(contentWidth * 0.62);
    rightLeft = 15 + leftWidth + 20;
    rightWidth = contentWidth - leftWidth - 35;

    app.ImageCard = uipanel(app.MainPanel, ...
        'Title', 'Image And ROI', ...
        'Position', [15 475 leftWidth 560], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [0.99 0.99 1.00]);

    app.ImageAxes = uiaxes(app.ImageCard, ...
        'Position', [15 15 leftWidth - 30 510], ...
        'Box', 'on');
    title(app.ImageAxes, 'Upload an image, then draw the plate ROI');
    axis(app.ImageAxes, 'off');

    app.ResultCard = uipanel(app.MainPanel, ...
        'Title', 'OCR Summary', ...
        'Position', [rightLeft 820 rightWidth 215], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [0.99 0.99 1.00]);

    app.BestTextLabel = uilabel(app.ResultCard, ...
        'Position', [20 118 rightWidth - 40 44], ...
        'Text', 'No OCR result yet', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 28, ...
        'FontWeight', 'bold', ...
        'FontColor', [0.15 0.20 0.28]);

    app.BestVariantLabel = uilabel(app.ResultCard, ...
        'Position', [20 86 rightWidth - 40 24], ...
        'Text', 'Best variant: -', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 12, ...
        'FontColor', [0.42 0.46 0.52]);

    app.ResultText = uitextarea(app.ResultCard, ...
        'Position', [14 14 rightWidth - 28 62], ...
        'Editable', 'off', ...
        'FontSize', 12, ...
        'Value', {'Results from each preprocessing variant will appear here.'});

    app.CropCard = uipanel(app.MainPanel, ...
        'Title', 'Selected Plate Crop', ...
        'Position', [rightLeft 555 rightWidth 235], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [0.99 0.99 1.00]);

    app.CropAxes = uiaxes(app.CropCard, ...
        'Position', [15 15 rightWidth - 30 185], ...
        'Box', 'on');
    title(app.CropAxes, 'ROI Crop');
    axis(app.CropAxes, 'off');

    variantWidth = floor((contentWidth - 45) / 3);
    variantY = 175;
    app.VariantAxes = gobjects(1, 6);
    app.VariantLabels = gobjects(1, 6);
    variantTitles = {'Gray', 'Enhanced', 'Dark Text', 'Bright Text', 'Inverted', 'Sharpened'};

    for i = 1:6
        rowIndex = floor((i - 1) / 3);
        colIndex = mod(i - 1, 3);
        panelLeft = 15 + colIndex * (variantWidth + 10);
        panelBottom = variantY - rowIndex * 235;

        variantPanel = uipanel(app.MainPanel, ...
            'Title', variantTitles{i}, ...
            'Position', [panelLeft panelBottom variantWidth 220], ...
            'FontWeight', 'bold', ...
            'BackgroundColor', [0.99 0.99 1.00]);

        app.VariantAxes(i) = uiaxes(variantPanel, ...
            'Position', [12 55 variantWidth - 24 135], ...
            'Box', 'on');
        axis(app.VariantAxes(i), 'off');

        app.VariantLabels(i) = uilabel(variantPanel, ...
            'Position', [12 12 variantWidth - 24 34], ...
            'Text', 'OCR: -', ...
            'FontSize', 11, ...
            'FontColor', [0.20 0.24 0.30]);
    end

    app.NotesCard = uipanel(app.MainPanel, ...
        'Title', 'How To Use', ...
        'Position', [15 15 contentWidth 125], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', [0.99 0.99 1.00]);

    app.NotesText = uitextarea(app.NotesCard, ...
        'Position', [12 12 contentWidth - 24 82], ...
        'Editable', 'off', ...
        'FontSize', 12, ...
        'Value', { ...
            '1. Upload an image.', ...
            '2. Click Draw ROI and drag the exact plate rectangle.', ...
            '3. Click Run OCR to compare several preprocessing variants.', ...
            '4. Use this to check whether OCR is failing because of the crop or because of preprocessing.'});

    guidata(app.Figure, app);

    function onUploadImage(~, ~)
        currentApp = guidata(app.Figure);
        [fileName, filePath] = uigetfile( ...
            {'*.jpg;*.jpeg;*.png;*.bmp', 'Image Files (*.jpg, *.jpeg, *.png, *.bmp)'}, ...
            'Select Image');
        if isequal(fileName, 0)
            return;
        end

        selectedPath = fullfile(filePath, fileName);
        currentApp.ImagePath = string(selectedPath);
        currentApp.Image = imread(selectedPath);
        currentApp.ROI = [];

        imshow(currentApp.Image, 'Parent', currentApp.ImageAxes);
        title(currentApp.ImageAxes, 'Draw the exact plate ROI');
        if ~isempty(currentApp.ROIHandle) && isvalid(currentApp.ROIHandle)
            delete(currentApp.ROIHandle);
        end
        currentApp.ROIHandle = [];

        currentApp.PathLabel.Text = ['Selected image: ' selectedPath];
        currentApp.StatusLabel.Text = 'Status: image loaded';
        currentApp.SelectROIButton.Enable = 'on';
        currentApp.AutoDetectButton.Enable = 'on';
        currentApp.RunOCRButton.Enable = 'off';

        clearVariantViews(currentApp);
        guidata(app.Figure, currentApp);
    end

    function onDrawROI(~, ~)
        currentApp = guidata(app.Figure);
        if isempty(currentApp.Image)
            return;
        end

        figure(currentApp.Figure);
        if ~isempty(currentApp.ROIHandle) && isvalid(currentApp.ROIHandle)
            delete(currentApp.ROIHandle);
        end

        currentApp.ROIHandle = drawrectangle(currentApp.ImageAxes, ...
            'Color', [0.12 0.86 0.35], ...
            'LineWidth', 2);
        addlistener(currentApp.ROIHandle, 'ROIMoved', @(~, evt) onROIChanged(evt));
        currentApp.ROI = round(currentApp.ROIHandle.Position);
        currentApp.RunOCRButton.Enable = 'on';
        currentApp.StatusLabel.Text = 'Status: ROI selected, ready for OCR';
        showCropPreview(currentApp);
        guidata(app.Figure, currentApp);
    end

    function onROIChanged(evt)
        currentApp = guidata(app.Figure);
        currentApp.ROI = round(evt.CurrentPosition);
        currentApp.RunOCRButton.Enable = 'on';
        showCropPreview(currentApp);
        guidata(app.Figure, currentApp);
    end

    function onAutoCrop(~, ~)
        currentApp = guidata(app.Figure);
        if isempty(currentApp.Image)
            return;
        end

        try
            result = extractCarPlateFromImage(currentApp.Image);
            if isempty(result.PlateBox)
                currentApp.StatusLabel.Text = 'Status: auto crop did not find a plate, draw ROI manually';
                guidata(app.Figure, currentApp);
                return;
            end

            if ~isempty(currentApp.ROIHandle) && isvalid(currentApp.ROIHandle)
                delete(currentApp.ROIHandle);
            end

            imshow(currentApp.Image, 'Parent', currentApp.ImageAxes);
            hold(currentApp.ImageAxes, 'on');
            rectangle(currentApp.ImageAxes, ...
                'Position', result.PlateBox, ...
                'EdgeColor', [0.12 0.86 0.35], ...
                'LineWidth', 2);
            hold(currentApp.ImageAxes, 'off');

            currentApp.ROI = round(result.PlateBox);
            currentApp.RunOCRButton.Enable = 'on';
            currentApp.StatusLabel.Text = 'Status: auto crop loaded, review it before OCR';
            showCropPreview(currentApp);
        catch cropError
            currentApp.StatusLabel.Text = ['Status: auto crop failed - ' cropError.message];
        end

        guidata(app.Figure, currentApp);
    end

    function onRunOCR(~, ~)
        currentApp = guidata(app.Figure);
        if isempty(currentApp.Image) || isempty(currentApp.ROI)
            return;
        end

        cropImage = safeCrop(currentApp.Image, currentApp.ROI);
        if isempty(cropImage)
            currentApp.StatusLabel.Text = 'Status: invalid ROI crop';
            guidata(app.Figure, currentApp);
            return;
        end

        [variantImages, variantNames, variantTexts, bestIndex] = runVariantOCR(cropImage);

        imshow(cropImage, 'Parent', currentApp.CropAxes);
        title(currentApp.CropAxes, 'ROI Crop');

        for i = 1:numel(variantImages)
            imshow(variantImages{i}, 'Parent', currentApp.VariantAxes(i));
            title(currentApp.VariantAxes(i), variantNames{i});
            currentApp.VariantLabels(i).Text = ['OCR: ' char(variantTexts(i))];
        end

        currentApp.BestTextLabel.Text = char(variantTexts(bestIndex));
        currentApp.BestVariantLabel.Text = ['Best variant: ' variantNames{bestIndex}];
        currentApp.ResultText.Value = composeResultLines(variantNames, variantTexts, bestIndex);
        currentApp.StatusLabel.Text = 'Status: OCR completed';

        guidata(app.Figure, currentApp);
    end

    function onClear(~, ~)
        currentApp = guidata(app.Figure);
        currentApp.Image = [];
        currentApp.ImagePath = "";
        currentApp.ROI = [];
        if ~isempty(currentApp.ROIHandle) && isvalid(currentApp.ROIHandle)
            delete(currentApp.ROIHandle);
        end
        currentApp.ROIHandle = [];

        cla(currentApp.ImageAxes);
        title(currentApp.ImageAxes, 'Upload an image, then draw the plate ROI');
        cla(currentApp.CropAxes);
        title(currentApp.CropAxes, 'ROI Crop');
        clearVariantViews(currentApp);

        currentApp.PathLabel.Text = 'Selected image: none';
        currentApp.StatusLabel.Text = 'Status: upload an image to begin';
        currentApp.BestTextLabel.Text = 'No OCR result yet';
        currentApp.BestVariantLabel.Text = 'Best variant: -';
        currentApp.ResultText.Value = {'Results from each preprocessing variant will appear here.'};
        currentApp.SelectROIButton.Enable = 'off';
        currentApp.AutoDetectButton.Enable = 'off';
        currentApp.RunOCRButton.Enable = 'off';

        guidata(app.Figure, currentApp);
    end
end

function cropImage = safeCrop(imageData, roi)
    roi = round(roi);
    x1 = max(1, roi(1));
    y1 = max(1, roi(2));
    x2 = min(size(imageData, 2), x1 + max(1, roi(3)) - 1);
    y2 = min(size(imageData, 1), y1 + max(1, roi(4)) - 1);

    if x2 <= x1 || y2 <= y1
        cropImage = [];
        return;
    end

    cropImage = imageData(y1:y2, x1:x2, :);
end

function showCropPreview(app)
    cropImage = safeCrop(app.Image, app.ROI);
    if isempty(cropImage)
        return;
    end
    imshow(cropImage, 'Parent', app.CropAxes);
    title(app.CropAxes, 'ROI Crop');
end

function clearVariantViews(app)
    for i = 1:numel(app.VariantAxes)
        cla(app.VariantAxes(i));
        axis(app.VariantAxes(i), 'off');
        app.VariantLabels(i).Text = 'OCR: -';
    end
end

function [variantImages, variantNames, variantTexts, bestIndex] = runVariantOCR(cropImage)
    if ndims(cropImage) == 3
        grayImage = rgb2gray(cropImage);
    else
        grayImage = cropImage;
    end

    grayImage = im2uint8(grayImage);
    enhanced = adapthisteq(grayImage, 'NumTiles', [8 8], 'ClipLimit', 0.02);
    sharpened = imsharpen(enhanced, 'Radius', 1.0, 'Amount', 1.2);

    darkText = imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'dark', 'Sensitivity', 0.42);
    darkText = cleanBinary(darkText);

    brightText = imbinarize(sharpened, 'adaptive', 'ForegroundPolarity', 'bright', 'Sensitivity', 0.48);
    brightText = cleanBinary(brightText);

    invertedImage = imcomplement(sharpened);

    variantImages = {
        grayImage
        enhanced
        darkText
        brightText
        invertedImage
        sharpened
    };

    variantNames = {'Gray', 'Enhanced', 'Dark Text', 'Bright Text', 'Inverted', 'Sharpened'};
    variantTexts = strings(numel(variantImages), 1);
    variantScores = -inf(numel(variantImages), 1);

    for i = 1:numel(variantImages)
        currentImage = variantImages{i};
        if islogical(currentImage)
            ocrInput = im2uint8(currentImage);
        else
            ocrInput = currentImage;
        end

        result = ocr(ocrInput, 'CharacterSet', 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-');
        currentText = formatOCRText(result.Text);
        variantTexts(i) = currentText;
        variantScores(i) = scoreOCRText(currentText, result);
    end

    [~, bestIndex] = max(variantScores);
end

function binaryImage = cleanBinary(binaryImage)
    binaryImage = imclearborder(binaryImage);
    binaryImage = bwareaopen(binaryImage, 8);
    binaryImage = imclose(binaryImage, strel('rectangle', [2 2]));
end

function textValue = formatOCRText(rawText)
    textValue = upper(string(rawText));
    textValue = regexprep(textValue, '[^A-Z0-9]', '');
end

function score = scoreOCRText(textValue, ocrResult)
    score = strlength(textValue) * 10;

    if ~isempty(ocrResult.CharacterConfidences)
        score = score + mean(ocrResult.CharacterConfidences, 'omitnan') / 5;
    end

    if strlength(textValue) >= 3 && strlength(textValue) <= 10
        score = score + 20;
    end

    if strlength(textValue) >= 5 && strlength(textValue) <= 8
        score = score + 15;
    end

    if any(isstrprop(char(textValue), 'alpha')) && any(isstrprop(char(textValue), 'digit'))
        score = score + 20;
    end
end

function lines = composeResultLines(variantNames, variantTexts, bestIndex)
    lines = strings(numel(variantNames) + 1, 1);
    lines(1) = "OCR comparison:";
    for i = 1:numel(variantNames)
        marker = " ";
        if i == bestIndex
            marker = "*";
        end
        lines(i + 1) = marker + " " + string(variantNames{i}) + ": " + variantTexts(i);
    end
    lines = cellstr(lines);
end
