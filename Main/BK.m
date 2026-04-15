function BK
%BK Scrollable MATLAB frontend for vehicle plate extraction.

    appFolder = fileparts(mfilename('fullpath'));
    if ~contains(path, appFolder)
        addpath(appFolder);
    end

    buildFrontend();
end

function app = buildFrontend()
    screenSize = get(groot, 'ScreenSize');
    windowWidth = min(1480, screenSize(3) - 80);
    windowHeight = min(900, screenSize(4) - 80);
    left = max(30, floor((screenSize(3) - windowWidth) / 2));
    bottom = max(30, floor((screenSize(4) - windowHeight) / 2));
    theme = getFrontendTheme();

    fig = uifigure( ...
        'Name', 'LPR / SIS Recognition Console', ...
        'Position', [left bottom windowWidth windowHeight], ...
        'Color', theme.FigureColor);

    mainPanel = uipanel(fig, ...
        'Position', [0 0 windowWidth windowHeight], ...
        'BorderType', 'none', ...
        'BackgroundColor', theme.FigureColor, ...
        'Scrollable', 'on');

    contentWidth = windowWidth - 30;
    contentHeight = 980;

    app = struct();
    app.Figure = fig;
    app.MainPanel = mainPanel;
    app.RootDir = fileparts(fileparts(mfilename('fullpath')));
    app.ImagePath = "";
    app.OriginalImage = [];
    app.Result = [];
    app.IsBusy = false;
    app.Theme = theme;

    app.HeaderCard = uipanel(mainPanel, ...
        'Position', [15 contentHeight - 170 contentWidth 145], ...
        'BackgroundColor', theme.CardColor, ...
        'BorderType', 'line', ...
        'HighlightColor', theme.BorderColor, ...
        'ForegroundColor', theme.TitleColor);

    uilabel(app.HeaderCard, ...
        'Position', [24 108 170 18], ...
        'Text', 'LPR / SIS READY', ...
        'FontSize', 11, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.AccentColor, ...
        'FontName', theme.LabelFont);

    app.Title = uilabel(app.HeaderCard, ...
        'Position', [24 68 720 40], ...
        'Text', 'License Plate Recognition Console', ...
        'FontSize', 30, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.TitleColor, ...
        'FontName', theme.TitleFont);

    app.Subtitle = uilabel(app.HeaderCard, ...
        'Position', [24 42 940 24], ...
        'Text', 'Professional dark-mode workspace for LPR and SIS review, built for cleaner recognition checks and evidence validation.', ...
        'FontSize', 13, ...
        'FontColor', theme.SubtleTextColor, ...
        'FontName', theme.BodyFont);

    app.UploadButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Open Vehicle Image', ...
        'Position', [24 12 150 32], ...
        'ButtonPushedFcn', @onUploadImage, ...
        'BackgroundColor', theme.AccentColor, ...
        'FontColor', [1 1 1], ...
        'FontWeight', 'bold', ...
        'FontName', theme.BodyFont);

    app.ExtractButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Run Recognition', ...
        'Position', [188 12 150 32], ...
        'ButtonPushedFcn', @onExtractPlate, ...
        'Enable', 'off', ...
        'BackgroundColor', theme.SuccessColor, ...
        'FontColor', [1 1 1], ...
        'FontWeight', 'bold', ...
        'FontName', theme.BodyFont);

    app.ClearButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Clear', ...
        'Position', [352 12 100 32], ...
        'ButtonPushedFcn', @onClearView, ...
        'BackgroundColor', theme.ButtonNeutral, ...
        'FontColor', theme.BodyTextColor, ...
        'FontName', theme.BodyFont);

    app.ReportButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Detailed Report', ...
        'Position', [466 12 140 32], ...
        'ButtonPushedFcn', @onOpenDetailedReport, ...
        'Enable', 'off', ...
        'BackgroundColor', theme.ButtonNeutral, ...
        'FontColor', theme.BodyTextColor, ...
        'FontName', theme.BodyFont);

    app.ExportReportButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Export Report', ...
        'Position', [620 12 140 32], ...
        'ButtonPushedFcn', @onExportDetailedReport, ...
        'Enable', 'off', ...
        'BackgroundColor', theme.ButtonNeutral, ...
        'FontColor', theme.BodyTextColor, ...
        'FontName', theme.BodyFont);

    app.FastModeCheckBox = uicheckbox(app.HeaderCard, ...
        'Text', 'Fast Mode', ...
        'Position', [792 16 110 22], ...
        'Value', true, ...
        'Tooltip', 'Fast mode runs v2 first, then v1 only. Full mode runs the full fallback chain.', ...
        'ValueChangedFcn', @onModeChanged, ...
        'FontColor', theme.BodyTextColor, ...
        'FontWeight', 'bold', ...
        'FontName', theme.BodyFont);

    app.ModeBadge = uilabel(app.HeaderCard, ...
        'Position', [910 12 132 30], ...
        'Text', 'PIPELINE: FAST', ...
        'HorizontalAlignment', 'center', ...
        'BackgroundColor', theme.PanelColor, ...
        'FontColor', theme.AccentSoftColor, ...
        'FontWeight', 'bold', ...
        'FontSize', 11, ...
        'FontName', theme.LabelFont);

    app.SystemBadge = uilabel(app.HeaderCard, ...
        'Position', [1056 12 180 30], ...
        'Text', 'SYSTEM: LPR + SIS', ...
        'HorizontalAlignment', 'center', ...
        'BackgroundColor', theme.PanelColor, ...
        'FontColor', theme.TitleColor, ...
        'FontWeight', 'bold', ...
        'FontSize', 11, ...
        'FontName', theme.LabelFont);

    app.PathLabel = uilabel(mainPanel, ...
        'Position', [24 contentHeight - 212 contentWidth - 48 24], ...
        'Text', 'Image source: none selected', ...
        'FontSize', 12, ...
        'FontColor', theme.SubtleTextColor, ...
        'FontName', theme.BodyFont);

    app.StatusLabel = uilabel(mainPanel, ...
        'Position', [24 contentHeight - 242 contentWidth - 48 24], ...
        'Text', 'System status: standby', ...
        'FontSize', 12, ...
        'FontColor', theme.AccentSoftColor, ...
        'FontWeight', 'bold', ...
        'FontName', theme.LabelFont);

    leftWidth = floor(contentWidth * 0.64);
    rightLeft = 15 + leftWidth + 20;
    rightWidth = contentWidth - leftWidth - 35;

    app.MainCard = uipanel(mainPanel, ...
        'Title', 'Vehicle Intake Preview', ...
        'Position', [15 15 leftWidth 690], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.MainAxes = uiaxes(app.MainCard, ...
        'Position', [18 18 leftWidth - 36 635], ...
        'Box', 'on');
    styleAppAxes(app.MainAxes, theme, 'Vehicle intake image');

    app.ResultCard = uipanel(mainPanel, ...
        'Title', 'Recognition Result', ...
        'Position', [rightLeft 595 rightWidth 110], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.ResultValue = uilabel(app.ResultCard, ...
        'Position', [20 44 rightWidth - 40 34], ...
        'Text', 'Awaiting input', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 28, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.TitleColor, ...
        'FontName', theme.ResultFont);

    app.ResultHint = uilabel(app.ResultCard, ...
        'Position', [20 14 rightWidth - 40 22], ...
        'Text', 'Validated plate reads and confidence notes will appear here.', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 12, ...
        'FontColor', theme.SubtleTextColor, ...
        'FontName', theme.BodyFont);

    app.ClassificationCard = uipanel(mainPanel, ...
        'Title', 'Plate Classification', ...
        'Position', [rightLeft 430 rightWidth 145], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.ClassificationValue = uilabel(app.ClassificationCard, ...
        'Position', [16 96 rightWidth - 32 24], ...
        'Text', 'Awaiting classification', ...
        'FontSize', 16, ...
        'FontWeight', 'bold', ...
        'HorizontalAlignment', 'center', ...
        'FontColor', theme.AccentSoftColor, ...
        'FontName', theme.LabelFont);

    app.ClassificationText = uitextarea(app.ClassificationCard, ...
        'Position', [14 14 rightWidth - 28 72], ...
        'Editable', 'off', ...
        'FontSize', 11, ...
        'BackgroundColor', theme.CardColor, ...
        'FontColor', theme.BodyTextColor, ...
        'FontName', theme.BodyFont, ...
        'Value', {'Plate class and registration family will appear here.'});

    app.PlateCard = uipanel(mainPanel, ...
        'Title', 'Plate Region Review', ...
        'Position', [rightLeft 220 rightWidth 190], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.PlateAxes = uiaxes(app.PlateCard, ...
        'Position', [14 14 rightWidth - 28 145], ...
        'Box', 'on');
    styleAppAxes(app.PlateAxes, theme, 'Plate crop');

    app.BinaryCard = uipanel(mainPanel, ...
        'Title', 'Segmentation Evidence', ...
        'Position', [rightLeft 15 rightWidth 185], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.BinaryAxes = uiaxes(app.BinaryCard, ...
        'Position', [14 14 rightWidth - 28 140], ...
        'Box', 'on');
    styleAppAxes(app.BinaryAxes, theme, 'Binary evidence');

    guidata(fig, app);

    function onUploadImage(~, ~)
        currentApp = guidata(fig);
        startFolder = fullfile(currentApp.RootDir, 'DataSet', 'images');
        if ~isfolder(startFolder)
            startFolder = pwd;
        end

        [fileName, filePath] = uigetfile( ...
            {'*.jpg;*.jpeg;*.png;*.bmp', 'Image Files (*.jpg, *.jpeg, *.png, *.bmp)'}, ...
            'Select Vehicle Image', ...
            startFolder);

        if isequal(fileName, 0)
            return;
        end

        selectedPath = fullfile(filePath, fileName);
        currentApp.ImagePath = string(selectedPath);
        currentApp.Result = [];

        try
            currentApp.OriginalImage = imread(selectedPath);
            showImageInAxes(currentApp.MainAxes, currentApp.OriginalImage, currentApp.Theme, 'Vehicle intake image');
            resetAxesPlaceholder(currentApp.PlateAxes, currentApp.Theme, 'Plate crop');
            resetAxesPlaceholder(currentApp.BinaryAxes, currentApp.Theme, 'Binary evidence');

            currentApp.PathLabel.Text = ['Image source: ' selectedPath];
            currentApp.StatusLabel.Text = 'System status: image loaded, ready for recognition';
            currentApp.ResultValue.Text = 'READY';
            currentApp.ResultValue.FontColor = currentApp.Theme.TitleColor;
            currentApp.ResultHint.Text = 'Run the LPR pipeline to produce a candidate plate read.';
            currentApp.ClassificationValue.Text = 'Awaiting classification';
            currentApp.ClassificationValue.FontColor = currentApp.Theme.AccentSoftColor;
            currentApp.ClassificationText.Value = { ...
                'Plate class and registration family will appear here.', ...
                'Run recognition to classify the detected Malaysian plate.'};
            currentApp.ExtractButton.Enable = 'on';
            currentApp.ReportButton.Enable = 'off';
            currentApp.ExportReportButton.Enable = 'off';
        catch readError
            currentApp.StatusLabel.Text = 'System status: image load failed';
            currentApp.ResultValue.Text = 'LOAD FAILED';
            currentApp.ResultValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ResultHint.Text = 'Check the selected image file and try again.';
            currentApp.ClassificationValue.Text = 'Unavailable';
            currentApp.ClassificationValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ClassificationText.Value = {['Error: ' readError.message]};
            currentApp.ExtractButton.Enable = 'off';
            currentApp.ReportButton.Enable = 'off';
            currentApp.ExportReportButton.Enable = 'off';
        end

        guidata(fig, currentApp);
    end

    function onExtractPlate(~, ~)
        currentApp = guidata(fig);
        if isfield(currentApp, 'IsBusy') && currentApp.IsBusy
            return;
        end
        if strlength(currentApp.ImagePath) == 0
            uialert(fig, 'Please upload an image first.', 'No Image Selected');
            return;
        end

        currentApp.IsBusy = true;
        useFastMode = currentApp.FastModeCheckBox.Value;
        if useFastMode
            currentApp.StatusLabel.Text = 'System status: running fast recognition (v2 -> v1)';
            extractOptions = struct('Mode', "fast", 'IncludeDebug', false, 'IncludeV4', false);
        else
            currentApp.StatusLabel.Text = 'System status: running full recognition (v2 -> v3 -> v1 -> v4)';
            extractOptions = struct('Mode', "full", 'IncludeDebug', true, 'IncludeV4', true);
        end
        currentApp.ResultValue.Text = 'SCANNING';
        currentApp.ResultValue.FontColor = currentApp.Theme.AccentColor;
        currentApp.ResultHint.Text = 'MATLAB is analyzing the image and validating the strongest candidate.';
        currentApp.ExtractButton.Enable = 'off';
        currentApp.ReportButton.Enable = 'off';
        currentApp.ExportReportButton.Enable = 'off';
        guidata(fig, currentApp);
        drawnow limitrate nocallbacks;

        try
            result = extractCarPlateFromImage(char(currentApp.ImagePath), extractOptions);
            if ~isvalid(fig)
                return;
            end
            currentApp = guidata(fig);
            currentApp.Result = result;
            showDetectionResult(currentApp, result);
            currentApp.StatusLabel.Text = 'System status: recognition completed';
            if ~useFastMode && hasDetailedReport(result)
                currentApp.ReportButton.Enable = 'on';
                currentApp.ExportReportButton.Enable = 'on';
            end
        catch extractionError
            currentApp.StatusLabel.Text = 'System status: recognition failed';
            currentApp.ResultValue.Text = 'FAILED';
            currentApp.ResultValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ResultHint.Text = 'The fallback pipeline could not finish cleanly.';
            currentApp.ClassificationValue.Text = 'Unavailable';
            currentApp.ClassificationValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ClassificationText.Value = { ...
                'Recognition could not be completed.', ...
                ['Error: ' extractionError.message], ...
                'Check OCR/Image Processing Toolbox availability and try another image.'};
            currentApp.ReportButton.Enable = 'off';
            currentApp.ExportReportButton.Enable = 'off';
        end

        currentApp.ExtractButton.Enable = 'on';
        currentApp.IsBusy = false;
        guidata(fig, currentApp);
    end

    function onModeChanged(~, ~)
        currentApp = guidata(fig);
        if currentApp.FastModeCheckBox.Value
            currentApp.StatusLabel.Text = 'System status: fast mode enabled';
            currentApp.ResultHint.Text = 'Fast mode runs v2 first, then v1 only.';
            currentApp.ModeBadge.Text = 'PIPELINE: FAST';
        else
            currentApp.StatusLabel.Text = 'System status: full mode enabled';
            currentApp.ResultHint.Text = 'Full mode runs the broader fallback pipeline for debugging.';
            currentApp.ModeBadge.Text = 'PIPELINE: FULL';
        end
        guidata(fig, currentApp);
    end

    function onClearView(~, ~)
        currentApp = guidata(fig);
        currentApp.ImagePath = "";
        currentApp.OriginalImage = [];
        currentApp.Result = [];

        cla(currentApp.MainAxes);
        resetAxesPlaceholder(currentApp.MainAxes, currentApp.Theme, 'Vehicle intake image');
        resetAxesPlaceholder(currentApp.PlateAxes, currentApp.Theme, 'Plate crop');
        resetAxesPlaceholder(currentApp.BinaryAxes, currentApp.Theme, 'Binary evidence');

        currentApp.PathLabel.Text = 'Image source: none selected';
        currentApp.StatusLabel.Text = 'System status: standby';
        currentApp.ResultValue.Text = 'Awaiting input';
        currentApp.ResultValue.FontColor = currentApp.Theme.TitleColor;
        currentApp.ResultHint.Text = 'Validated plate reads and confidence notes will appear here.';
        currentApp.ClassificationValue.Text = 'Awaiting classification';
        currentApp.ClassificationValue.FontColor = currentApp.Theme.AccentSoftColor;
        currentApp.ClassificationText.Value = { ...
            'Plate class and registration family will appear here.', ...
            'Supported groups include civilian, military, diplomatic, special series, and temporary/trade formats.'};
        currentApp.ExtractButton.Enable = 'off';
        currentApp.ReportButton.Enable = 'off';
        currentApp.ExportReportButton.Enable = 'off';

        guidata(fig, currentApp);
    end

    function onOpenDetailedReport(~, ~)
        currentApp = guidata(fig);
        if isempty(currentApp.Result) || ~hasDetailedReport(currentApp.Result)
            uialert(fig, 'Run plate extraction first to generate the debug report.', 'No Report Available');
            return;
        end

        try
            showDetailedReportWindow(currentApp.Result);
        catch reportError
            warning('PlateReport:OpenFailed', 'Detailed report window failed: %s', reportError.message);
            uialert(fig, sprintf('Could not open the detailed report window.%s%s', ...
                newline, reportError.message), ...
                'Detailed Report Error', 'Icon', 'warning');
        end
    end

    function onExportDetailedReport(~, ~)
        currentApp = guidata(fig);
        if isfield(currentApp, 'IsBusy') && currentApp.IsBusy
            return;
        end
        if isempty(currentApp.Result) || ~hasDetailedReport(currentApp.Result)
            uialert(fig, 'Run plate extraction first to generate the debug report.', 'No Report Available');
            return;
        end

        currentApp.IsBusy = true;
        currentApp.ExportReportButton.Enable = 'off';
        guidata(fig, currentApp);
        drawnow limitrate nocallbacks;

        try
            exportFolder = exportDetailedReport(currentApp.Result);
            uialert(fig, sprintf('Detailed report saved to:%s%s', newline, exportFolder), ...
                'Report Saved', 'Icon', 'success');
        catch exportError
            warning('PlateReport:ExportFailed', 'Detailed report export failed: %s', exportError.message);
            try
                fallbackFolder = exportDetailedReportFallback(currentApp.Result);
                uialert(fig, sprintf(['Detailed report export hit a graphics issue.%s%s%s' ...
                    'Saved fallback report to:%s%s'], ...
                    newline, exportError.message, newline, newline, fallbackFolder), ...
                    'Report Saved With Fallback', 'Icon', 'warning');
            catch fallbackError
                warning('PlateReport:FallbackExportFailed', ...
                    'Fallback detailed report export failed: %s', fallbackError.message);
                uialert(fig, sprintf(['Detailed report export failed.%s%s%s' ...
                    'Fallback export also failed:%s%s'], ...
                    newline, exportError.message, newline, newline, fallbackError.message), ...
                    'Report Export Error', 'Icon', 'error');
            end
        end

        if isvalid(fig)
            currentApp = guidata(fig);
            currentApp.IsBusy = false;
            if ~isempty(currentApp.Result) && hasDetailedReport(currentApp.Result)
                currentApp.ExportReportButton.Enable = 'on';
            end
            guidata(fig, currentApp);
        end
    end
end

function showDetectionResult(app, result)
    theme = app.Theme;
    plateClass = classifyMalaysianPlate(result.PlateText);
    mainTitle = 'Vehicle intake image';
    if ~isempty(result.PlateBox) && result.IsPlateTextValid
        mainTitle = ['Detected Plate: ' char(result.PlateText)];
    elseif ~isempty(result.PlateBox)
        mainTitle = 'Plate Region Detected';
    elseif ~isempty(result.CandidateBoxes)
        mainTitle = 'No Reliable Plate Found';
    end
    showImageInAxes(app.MainAxes, buildAnnotatedMainImage(result), theme, mainTitle);

    if ~isempty(result.PlateImage)
        showImageInAxes(app.PlateAxes, result.PlateImage, theme, 'Detected plate crop');
    else
        resetAxesPlaceholder(app.PlateAxes, theme, 'Detected plate crop');
    end

    if ~isempty(result.BinaryPlate)
        showImageInAxes(app.BinaryAxes, result.BinaryPlate, theme, 'Binary plate evidence');
    else
        resetAxesPlaceholder(app.BinaryAxes, theme, 'Binary plate evidence');
    end

    if result.IsPlateTextValid
        app.ResultValue.Text = char(result.PlateText);
        app.ResultValue.FontColor = theme.SuccessColor;
        app.ResultHint.Text = ['Accepted by detector ' char(result.MethodUsed) '.'];
    elseif ~isempty(result.PlateBox)
        app.ResultValue.Text = 'REVIEW REQUIRED';
        app.ResultValue.FontColor = theme.WarningColor;
        if strlength(result.PlateText) > 0
            app.ResultHint.Text = 'Plate candidate found, but OCR is not reliable enough for final acceptance.';
        else
            app.ResultHint.Text = 'A region was found, but none of the fallback OCR results looked plate-like.';
        end
    else
        app.ResultValue.Text = 'NO MATCH';
        app.ResultValue.FontColor = theme.ErrorColor;
        app.ResultHint.Text = 'No strong plate candidate matched the current rules.';
    end

    app.ClassificationValue.Text = buildClassificationHeadline(plateClass);
    app.ClassificationValue.FontColor = plateClass.Color;
    app.ClassificationText.Value = buildClassificationLines(result, plateClass);
end

function headline = buildClassificationHeadline(plateClass)
    if strlength(string(plateClass.State)) > 0 && ...
            ~strcmpi(char(string(plateClass.State)), 'Unknown') && ...
            ~strcmpi(char(string(plateClass.State)), 'Unknown / special series') && ...
            ~strcmpi(char(string(plateClass.State)), 'Varies') && ...
            ~strcmpi(char(string(plateClass.State)), 'Not state-based')
        headline = plateClass.Category + " (" + plateClass.State + ")";
    else
        headline = plateClass.Category;
    end
end

function lines = buildClassificationLines(result, plateClass)
    lines = {
        ['Text: ' char(string(result.PlateText))]
        ['Family: ' plateClass.Family]
        ['Group: ' plateClass.Group]
        ['Detector: ' char(string(result.MethodUsed))]
    };
end

function plateClass = classifyMalaysianPlate(textValue)
    theme = getFrontendTheme();
    cleaned = upper(regexprep(string(textValue), '[^A-Z0-9-]', ''));

    plateClass = struct( ...
        'Category', 'Unknown / Unconfirmed', ...
        'Family', 'Unrecognized format', ...
        'Group', 'Manual review required', ...
        'State', 'Unknown', ...
        'Color', theme.WarningColor);

    if strlength(cleaned) == 0
        plateClass.Color = theme.ErrorColor;
        return;
    end

    compact = regexprep(cleaned, '-', '');

    if ~isempty(regexp(char(cleaned), '^\d{2}-\d{2}-(DC|CC|UN|PA)$', 'once')) || ...
            ~isempty(regexp(char(compact), '^\d{4}(DC|CC|UN|PA)$', 'once'))
        plateClass.Category = 'Diplomatic / International';
        plateClass.Family = 'Diplomatic or international mission plate';
        plateClass.Group = 'Diplomatic / international plates';
        plateClass.State = 'Not state-based';
        plateClass.Color = theme.AccentColor;
        return;
    end

    if ~isempty(regexp(char(cleaned), '^Z[A-Z0-9]{1,7}$', 'once'))
        plateClass.Category = 'Military Plate';
        plateClass.Family = 'Malaysian Armed Forces Z-prefix family';
        plateClass.Group = 'Military plates';
        plateClass.State = 'Not state-based';
        plateClass.Color = theme.WarningColor;
        return;
    end

    if ~isempty(regexp(char(cleaned), '^(KV|PROTON|PUTRAJAYA|SUKOM|MALAYSIA|GOLDEN|PATRIOT|PERFECT|NAAM|VIP|GT|RIMAU)[A-Z0-9]{0,6}$', 'once'))
        plateClass.Category = 'Special Series Plate';
        plateClass.Family = 'Commemorative, premium, or event-linked series';
        plateClass.Group = 'Special series plates';
        plateClass.State = 'Varies';
        plateClass.Color = theme.AccentSoftColor;
        return;
    end

    if ~isempty(regexp(char(compact), '^[A-Z]{1,4}\d{1,4}[A-Z]?$', 'once'))
        prefix = regexp(char(compact), '^[A-Z]+', 'match', 'once');
        stateName = lookupStatePrefix(prefix);
        plateClass.Category = 'Normal Civilian Plate';
        plateClass.Family = 'Private or commercial Malaysian registration';
        plateClass.Group = 'Normal civilian plates';
        plateClass.State = stateName;
        plateClass.Color = theme.SuccessColor;
        return;
    end

    if ~isempty(regexp(char(cleaned), '^(TMP|TR|A\/F)[A-Z0-9-]{1,8}$', 'once'))
        plateClass.Category = 'Temporary / Trade Plate';
        plateClass.Family = 'Temporary registration or dealer/trade family';
        plateClass.Group = 'Temporary / trade plates';
        plateClass.State = 'Varies';
        plateClass.Color = theme.WarningColor;
        return;
    end

    if ~isempty(regexp(char(cleaned), '^[A-Z]{1,5}\d{1,4}$', 'once'))
        plateClass.Category = 'Special Series Plate';
        plateClass.Family = 'Likely premium or commemorative registration';
        plateClass.Group = 'Special series plates';
        plateClass.State = 'Varies';
        plateClass.Color = theme.AccentSoftColor;
    end
end

function stateName = lookupStatePrefix(prefix)
    stateName = 'Unknown / special series';
    if strlength(string(prefix)) == 0
        return;
    end

    prefix = upper(string(prefix));
    key = extractBefore(prefix + " ", 2);

    switch char(key)
        case 'A'
            stateName = 'Perak';
        case 'B'
            stateName = 'Selangor';
        case 'C'
            stateName = 'Pahang';
        case 'D'
            stateName = 'Kelantan';
        case 'J'
            stateName = 'Johor';
        case 'K'
            stateName = 'Kedah';
        case 'M'
            stateName = 'Malacca';
        case 'N'
            stateName = 'Negeri Sembilan';
        case 'P'
            stateName = 'Penang';
        case 'R'
            stateName = 'Perlis';
        case 'T'
            stateName = 'Terengganu';
        case {'W', 'V'}
            stateName = 'Kuala Lumpur';
        case 'L'
            stateName = 'Labuan';
        case 'F'
            stateName = 'Putrajaya';
        case 'Q'
            stateName = 'Sarawak';
        case 'S'
            stateName = 'Sabah';
    end
end

function tf = hasDetailedReport(result)
    tf = isstruct(result) && isfield(result, 'DebugReport') && ...
        isstruct(result.DebugReport) && isfield(result.DebugReport, 'Attempts') && ...
        ~isempty(result.DebugReport.Attempts);
end

function showDetailedReportWindow(result)
    report = result.DebugReport;
    theme = getFrontendTheme();
    windowWidth = 1280;
    windowHeight = 820;
    totalHeight = 90;
    cardWidth = 1220;
    for i = 1:numel(report.Attempts)
        stepCount = numel(report.Attempts(i).Steps);
        stepRows = max(1, ceil(stepCount / 2));
        totalHeight = totalHeight + 120 + stepRows * 290 + 20;
    end
    canvasHeight = max(820, totalHeight);

    reportFigure = uifigure( ...
        'Name', 'Plate Detection Detailed Report', ...
        'Position', [80 60 windowWidth windowHeight], ...
        'Color', theme.FigureColor);

    scrollPanel = uipanel(reportFigure, ...
        'Position', [0 0 windowWidth windowHeight], ...
        'BorderType', 'none', ...
        'BackgroundColor', theme.FigureColor, ...
        'Scrollable', 'on');

    headerText = sprintf('Methods tried: %s | Selected: %s', ...
        strjoin(cellstr(report.AttemptedMethods), ' -> '), char(report.SelectedMethod));
    uilabel(scrollPanel, ...
        'Position', [20 canvasHeight - 48 1200 28], ...
        'Text', headerText, ...
        'FontSize', 16, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    yTop = canvasHeight - 80;

    for i = 1:numel(report.Attempts)
        attempt = report.Attempts(i);
        stepCount = numel(attempt.Steps);
        stepRows = max(1, ceil(stepCount / 2));
        cardHeight = 120 + stepRows * 290;

        card = uipanel(scrollPanel, ...
            'Title', sprintf('Method %s | Status: %s', upper(char(attempt.Method)), char(attempt.Status)), ...
            'Position', [20 yTop - cardHeight cardWidth cardHeight], ...
            'FontWeight', 'bold', ...
            'BackgroundColor', theme.CardColor, ...
            'ForegroundColor', theme.TitleColor, ...
            'FontName', theme.LabelFont);

        notesText = char(string(attempt.Notes));
        if strlength(string(attempt.Notes)) == 0
            notesText = 'No additional notes.';
        end

        uilabel(card, ...
            'Position', [14 cardHeight - 48 cardWidth - 28 28], ...
            'Text', notesText, ...
            'FontSize', 12, ...
            'FontColor', theme.SubtleTextColor, ...
            'FontName', theme.BodyFont);

        for stepIndex = 1:stepCount
            currentStep = attempt.Steps(stepIndex);
            rowIndex = floor((stepIndex - 1) / 2);
            colIndex = mod(stepIndex - 1, 2);
            panelWidth = floor((cardWidth - 42) / 2);
            stepX = 14 + colIndex * (panelWidth + 14);
            stepY = cardHeight - 90 - (rowIndex + 1) * 270;

            stepPanel = uipanel(card, ...
                'Title', char(currentStep.Title), ...
                'Position', [stepX stepY panelWidth 250], ...
                'BackgroundColor', theme.PanelColor, ...
                'ForegroundColor', theme.TitleColor, ...
                'FontName', theme.LabelFont);

            stepAxes = uiaxes(stepPanel, ...
                'Position', [10 48 panelWidth - 20 180], ...
                'Box', 'on');
            styleAppAxes(stepAxes, theme, 'No image available');

            if ~isempty(currentStep.Image)
                showImageInAxes(stepAxes, currentStep.Image, theme, char(currentStep.Title));
            else
                title(stepAxes, 'No image available');
            end

            stepDescription = char(string(currentStep.Description));
            uitextarea(stepPanel, ...
                'Position', [10 8 panelWidth - 20 36], ...
                'Editable', 'off', ...
                'Value', {stepDescription}, ...
                'FontSize', 11, ...
                'BackgroundColor', theme.PanelColor, ...
                'FontColor', theme.BodyTextColor, ...
                'FontName', theme.BodyFont);
        end

        if stepCount == 0
            uitextarea(card, ...
                'Position', [14 14 cardWidth - 28 cardHeight - 80], ...
                'Editable', 'off', ...
                'Value', {'No intermediate steps were captured for this method.'}, ...
                'FontSize', 12, ...
                'BackgroundColor', theme.CardColor, ...
                'FontColor', theme.BodyTextColor, ...
                'FontName', theme.BodyFont);
        end

        yTop = yTop - cardHeight - 20;
    end
end

function exportFolder = exportDetailedReport(result)
    report = result.DebugReport;
    reportRoot = fullfile(getDefaultDownloadsFolder(), 'PlateDetectionReports');
    if ~isfolder(reportRoot)
        mkdir(reportRoot);
    end

    timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    exportFolder = fullfile(reportRoot, ['PlateReport_' char(timestamp)]);
    mkdir(exportFolder);

    try
        exportCombinedDetailedReport(result, exportFolder);
    catch exportError
        warning('PlateReport:CombinedExportFailed', ...
            'Combined report export failed: %s', exportError.message);
        rethrow(exportError);
    end

    for i = 1:numel(report.Attempts)
        attempt = report.Attempts(i);
        methodFolder = fullfile(exportFolder, upper(char(attempt.Method)));
        if ~isfolder(methodFolder)
            mkdir(methodFolder);
        end
        writeAttemptFallbackSummary(attempt, methodFolder, []);
    end
end

function exportFolder = exportDetailedReportFallback(result)
    report = result.DebugReport;
    reportRoot = fullfile(getDefaultDownloadsFolder(), 'PlateDetectionReports');
    if ~isfolder(reportRoot)
        mkdir(reportRoot);
    end

    timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    exportFolder = fullfile(reportRoot, ['PlateReport_Fallback_' char(timestamp)]);
    mkdir(exportFolder);

    for i = 1:numel(report.Attempts)
        attempt = report.Attempts(i);
        methodFolder = fullfile(exportFolder, upper(char(attempt.Method)));
        if ~isfolder(methodFolder)
            mkdir(methodFolder);
        end
        writeAttemptFallbackSummary(attempt, methodFolder, []);
    end
end

function folderPath = getDefaultDownloadsFolder()
    userProfile = getenv('USERPROFILE');
    if ~isempty(userProfile)
        downloadsPath = fullfile(userProfile, 'Downloads');
        if isfolder(downloadsPath)
            folderPath = downloadsPath;
            return;
        end
    end

    folderPath = pwd;
end

function safeName = sanitizeFileName(fileName)
    safeName = regexprep(string(fileName), '[^A-Za-z0-9_-]', '_');
    safeName = regexprep(safeName, '_+', '_');
    safeName = char(safeName);
end

function writableImage = makeWritableImage(imageData)
    if islogical(imageData)
        writableImage = uint8(imageData) * 255;
        return;
    end

    if isa(imageData, 'uint8') || isa(imageData, 'uint16')
        writableImage = imageData;
        return;
    end

    if isfloat(imageData)
        writableImage = im2uint8(mat2gray(imageData));
        return;
    end

    writableImage = im2uint8(imageData);
end

function exportMethodReportImage(attempt, methodFolder)
    exportFigure = buildAttemptReportFigure(attempt);
    cleanupFigure = onCleanup(@() close(exportFigure)); %#ok<NASGU>

    methodName = upper(char(attempt.Method));
    reportImagePath = fullfile(methodFolder, sprintf('%s_report.png', methodName));
    reportPdfPath = fullfile(methodFolder, sprintf('%s_report.pdf', methodName));
    exportgraphics(exportFigure, reportImagePath, 'Resolution', 200);
    exportgraphics(exportFigure, reportPdfPath, 'ContentType', 'image');
end

function exportCombinedDetailedReport(result, exportFolder)
    report = result.DebugReport;
    combinedPdfPath = fullfile(exportFolder, 'combined_report.pdf');
    if isfile(combinedPdfPath)
        delete(combinedPdfPath);
    end

    summaryFigure = buildCombinedSummaryFigure(report);
    cleanupSummary = onCleanup(@() close(summaryFigure)); %#ok<NASGU>
    exportgraphics(summaryFigure, combinedPdfPath, 'ContentType', 'image');

    for i = 1:numel(report.Attempts)
        attemptFigure = buildAttemptReportFigure(report.Attempts(i));
        cleanupAttempt = onCleanup(@() close(attemptFigure)); %#ok<NASGU>
        exportgraphics(attemptFigure, combinedPdfPath, 'ContentType', 'image', 'Append', true);
    end
end

function exportFigure = buildAttemptReportFigure(attempt)
    stepCount = numel(attempt.Steps);
    stepRows = max(1, ceil(stepCount / 2));
    cardWidth = 1400;
    cardHeight = 240 + stepRows * 340;

    exportFigure = figure( ...
        'Visible', 'off', ...
        'Color', [1 1 1], ...
        'Position', [100 100 cardWidth cardHeight], ...
        'PaperPositionMode', 'auto', ...
        'InvertHardcopy', 'off');

    notesText = char(string(attempt.Notes));
    if strlength(string(attempt.Notes)) == 0
        notesText = 'No additional notes.';
    end

    annotation(exportFigure, 'textbox', [0.02 0.965 0.96 0.03], ...
        'String', sprintf('Method %s | Status: %s', upper(char(attempt.Method)), char(attempt.Status)), ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 13, ...
        'Color', [0.10 0.12 0.16], 'Interpreter', 'none');
    annotation(exportFigure, 'textbox', [0.02 0.935 0.96 0.028], ...
        'String', notesText, ...
        'EdgeColor', 'none', 'FontSize', 11, 'Color', [0.36 0.40 0.46], ...
        'Interpreter', 'none');

    tiled = tiledlayout(exportFigure, stepRows, 2, ...
        'Padding', 'compact', 'TileSpacing', 'compact');

    for stepIndex = 1:stepCount
        currentStep = attempt.Steps(stepIndex);
        ax = nexttile(tiled);
        axis(ax, 'off', 'image');
        if isprop(ax, 'Toolbar')
            ax.Toolbar.Visible = 'off';
        end

        if ~isempty(currentStep.Image)
            imageData = makeWritableImage(currentStep.Image);
            imshow(imageData, 'Parent', ax);
        else
            text(ax, 0.5, 0.5, sprintf('No debug image available for Step %d', stepIndex), ...
                'HorizontalAlignment', 'center', 'Units', 'normalized', ...
                'Color', [0.25 0.25 0.25], 'FontSize', 11);
        end

        title(ax, char(string(currentStep.Title)), 'Interpreter', 'none', 'FontSize', 11);
        descText = char(string(currentStep.Description));
        if strlength(string(currentStep.Description)) == 0
            descText = 'No description available.';
        end
        text(ax, 0.02, 0.02, descText, ...
            'Units', 'normalized', ...
            'Interpreter', 'none', ...
            'FontSize', 9, ...
            'Color', [0.20 0.20 0.20], ...
            'BackgroundColor', [1 1 1], ...
            'Margin', 2, ...
            'VerticalAlignment', 'bottom', ...
            'HorizontalAlignment', 'left');
    end

    drawnow;
    pause(0.1);
end

function exportFigure = buildCombinedSummaryFigure(report)
    exportFigure = figure( ...
        'Visible', 'off', ...
        'Color', [1 1 1], ...
        'Position', [100 100 1200 900], ...
        'PaperPositionMode', 'auto', ...
        'InvertHardcopy', 'off');

    annotation(exportFigure, 'textbox', [0.05 0.93 0.90 0.04], ...
        'String', sprintf('Combined Plate Detection Report | Selected: %s', char(report.SelectedMethod)), ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 18, ...
        'Interpreter', 'none', 'Color', [0.10 0.12 0.16]);
    annotation(exportFigure, 'textbox', [0.05 0.89 0.90 0.03], ...
        'String', sprintf('Methods tried: %s', strjoin(cellstr(report.AttemptedMethods), ' -> ')), ...
        'EdgeColor', 'none', 'FontSize', 11, 'Interpreter', 'none', ...
        'Color', [0.35 0.40 0.46]);

    yPos = 0.82;
    for i = 1:numel(report.Attempts)
        attempt = report.Attempts(i);
        stepCount = numel(attempt.Steps);
        noteText = char(string(attempt.Notes));
        if strlength(string(attempt.Notes)) == 0
            noteText = 'No additional notes.';
        end

        annotation(exportFigure, 'textbox', [0.05 yPos 0.90 0.09], ...
            'String', sprintf(['Method %s\nStatus: %s\nSteps: %d\nNotes: %s'], ...
            upper(char(attempt.Method)), char(attempt.Status), stepCount, noteText), ...
            'EdgeColor', [0.82 0.84 0.88], ...
            'BackgroundColor', [0.98 0.98 0.99], ...
            'FontSize', 11, ...
            'Interpreter', 'none', ...
            'Color', [0.18 0.20 0.24]);
        yPos = yPos - 0.12;
    end

    annotation(exportFigure, 'textbox', [0.05 0.05 0.90 0.06], ...
        'String', 'Each following page contains the full exported step images for one detector attempt.', ...
        'EdgeColor', 'none', 'FontSize', 10, 'Interpreter', 'none', ...
        'Color', [0.35 0.40 0.46]);
    drawnow;
    pause(0.1);
end

function theme = getFrontendTheme()
    theme = struct( ...
        'FigureColor', [0.06 0.08 0.11], ...
        'CardColor', [0.10 0.13 0.18], ...
        'PanelColor', [0.13 0.17 0.23], ...
        'BorderColor', [0.20 0.27 0.35], ...
        'TitleColor', [0.92 0.95 0.98], ...
        'BodyTextColor', [0.82 0.87 0.92], ...
        'SubtleTextColor', [0.56 0.65 0.74], ...
        'AccentColor', [0.13 0.65 0.96], ...
        'AccentSoftColor', [0.48 0.80 1.00], ...
        'SuccessColor', [0.18 0.75 0.49], ...
        'WarningColor', [0.95 0.72 0.24], ...
        'ErrorColor', [0.95 0.39 0.39], ...
        'ButtonNeutral', [0.18 0.22 0.29], ...
        'TitleFont', 'Bahnschrift', ...
        'LabelFont', 'Segoe UI Semibold', ...
        'BodyFont', 'Segoe UI', ...
        'ResultFont', 'Consolas');
end

function styleAppAxes(ax, theme, titleText)
    cla(ax);
    ax.Color = theme.PanelColor;
    ax.XColor = theme.PanelColor;
    ax.YColor = theme.PanelColor;
    ax.Box = 'on';
    ax.Toolbar.Visible = 'off';
    title(ax, titleText, ...
        'Color', theme.SubtleTextColor, ...
        'FontName', theme.LabelFont, ...
        'FontSize', 12);
    axis(ax, 'off');
end

function resetAxesPlaceholder(ax, theme, titleText)
    styleAppAxes(ax, theme, titleText);
end

function showImageInAxes(ax, imageData, theme, titleText)
    if ~isvalid(ax)
        return;
    end
    delete(ax.Children);
    ax.Color = theme.PanelColor;
    ax.XColor = theme.PanelColor;
    ax.YColor = theme.PanelColor;
    ax.Box = 'on';
    if isprop(ax, 'Toolbar') && ~isempty(ax.Toolbar)
        ax.Toolbar.Visible = 'off';
    end
    ax.Visible = 'off';

    if islogical(imageData)
        displayImage = uint8(imageData) * 255;
    elseif isa(imageData, 'uint8') || isa(imageData, 'uint16')
        displayImage = imageData;
    elseif isfloat(imageData)
        displayImage = im2uint8(mat2gray(imageData));
    else
        displayImage = im2uint8(imageData);
    end

    image(ax, displayImage);
    axis(ax, 'image');
    axis(ax, 'off');
    title(ax, titleText, ...
        'Color', theme.SubtleTextColor, ...
        'FontName', theme.LabelFont, ...
        'FontSize', 12);
end

function annotatedImage = buildAnnotatedMainImage(result)
    if ndims(result.Image) == 2
        annotatedImage = repmat(im2uint8(result.Image), 1, 1, 3);
    else
        annotatedImage = im2uint8(result.Image);
    end

    if ~isempty(result.CandidateBoxes)
        annotatedImage = insertShape(annotatedImage, 'Rectangle', double(result.CandidateBoxes), ...
            'Color', 'yellow', 'LineWidth', 1);
    end

    if ~isempty(result.PlateBox)
        annotatedImage = insertShape(annotatedImage, 'Rectangle', double(result.PlateBox), ...
            'Color', 'green', 'LineWidth', 3);

        if result.IsPlateTextValid && strlength(string(result.PlateText)) > 0
            labelPos = [double(result.PlateBox(1)), max(1, double(result.PlateBox(2) - 24))];
            annotatedImage = insertText(annotatedImage, labelPos, char(string(result.PlateText)), ...
                'TextColor', 'yellow', ...
                'BoxColor', 'black', ...
                'BoxOpacity', 0.75, ...
                'FontSize', 18);
        end
    end
end

function writeAttemptFallbackSummary(attempt, methodFolder, exportError)
    summaryPath = fullfile(methodFolder, 'report_summary.txt');
    fid = fopen(summaryPath, 'w');
    if fid == -1
        return;
    end
    cleanupFile = onCleanup(@() fclose(fid));

    fprintf(fid, 'Method: %s\n', upper(char(attempt.Method)));
    fprintf(fid, 'Status: %s\n', char(string(attempt.Status)));
    fprintf(fid, 'Notes: %s\n', char(string(attempt.Notes)));
    if ~isempty(exportError)
        fprintf(fid, 'Export error: %s\n', exportError.message);
    end
    fprintf(fid, '\nSteps:\n');

    for i = 1:numel(attempt.Steps)
        currentStep = attempt.Steps(i);
        fprintf(fid, '%d. %s\n', i, char(string(currentStep.Title)));
        fprintf(fid, '   %s\n', char(string(currentStep.Description)));
    end

    clear cleanupFile;
end
