%% 
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
        'Name', 'License Plate Recognition Console', ...
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
        'Position', [24 108 240 18], ...
        'Text', 'LICENSE PLATE RECOGNITION', ...
        'FontSize', 11, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.AccentColor, ...
        'FontName', theme.LabelFont);

    app.Title = uilabel(app.HeaderCard, ...
        'Position', [24 68 900 40], ...
        'Text', 'License Plate Recognition Console', ...
        'FontSize', 30, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.TitleColor, ...
        'FontName', theme.TitleFont);

    app.Subtitle = uilabel(app.HeaderCard, ...
        'Position', [24 42 940 24], ...
        'Text', 'Upload a vehicle image to extract and classify its registration plate.', ...
        'FontSize', 13, ...
        'FontColor', theme.SubtleTextColor, ...
        'FontName', theme.BodyFont);

    app.UploadButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Open Image', ...
        'Position', [24 12 150 32], ...
        'ButtonPushedFcn', @onUploadImage, ...
        'BackgroundColor', theme.AccentColor, ...
        'FontColor', [1 1 1], ...
        'FontWeight', 'bold', ...
        'FontName', theme.BodyFont);

    app.ExtractButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Scan Plate', ...
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
        'Position', [466 12 150 32], ...
        'ButtonPushedFcn', @onOpenDetailedReport, ...
        'Enable', 'off', ...
        'BackgroundColor', theme.ButtonNeutral, ...
        'FontColor', theme.BodyTextColor, ...
        'FontName', theme.BodyFont);

    app.ExportReportButton = uibutton(app.HeaderCard, 'push', ...
        'Text', 'Export Report', ...
        'Position', [630 12 150 32], ...
        'ButtonPushedFcn', @onExportDetailedReport, ...
        'Enable', 'off', ...
        'BackgroundColor', theme.ButtonNeutral, ...
        'FontColor', theme.BodyTextColor, ...
        'FontName', theme.BodyFont);

    app.PathLabel = uilabel(mainPanel, ...
        'Position', [24 contentHeight - 212 contentWidth - 48 24], ...
        'Text', 'Source image: none selected', ...
        'FontSize', 12, ...
        'FontColor', theme.SubtleTextColor, ...
        'FontName', theme.BodyFont);

    app.StatusLabel = uilabel(mainPanel, ...
        'Position', [24 contentHeight - 242 contentWidth - 48 24], ...
        'Text', 'Status: idle', ...
        'FontSize', 12, ...
        'FontColor', theme.AccentSoftColor, ...
        'FontWeight', 'bold', ...
        'FontName', theme.LabelFont);

    leftWidth = floor(contentWidth * 0.64);
    rightLeft = 15 + leftWidth + 20;
    rightWidth = contentWidth - leftWidth - 35;

    app.MainCard = uipanel(mainPanel, ...
        'Title', 'Vehicle Image', ...
        'Position', [15 15 leftWidth 690], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.MainAxes = uiaxes(app.MainCard, ...
        'Position', [18 18 leftWidth - 36 635], ...
        'Box', 'on');
    styleAppAxes(app.MainAxes, theme, 'No image loaded');

    app.ResultCard = uipanel(mainPanel, ...
        'Title', 'Recognition Result', ...
        'Position', [rightLeft 595 rightWidth 110], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.ResultValue = uilabel(app.ResultCard, ...
        'Position', [20 44 rightWidth - 40 34], ...
        'Text', '—', ...
        'HorizontalAlignment', 'center', ...
        'FontSize', 28, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.TitleColor, ...
        'FontName', theme.ResultFont);

    app.ResultHint = uilabel(app.ResultCard, ...
        'Position', [20 14 rightWidth - 40 22], ...
        'Text', 'The recognized registration number will appear here.', ...
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
        'Text', '—', ...
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
        'Value', {'Plate category, family, and registration group will appear here.'});

    app.PlateCard = uipanel(mainPanel, ...
        'Title', 'Detected Plate Region', ...
        'Position', [rightLeft 220 rightWidth 190], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.PlateAxes = uiaxes(app.PlateCard, ...
        'Position', [14 14 rightWidth - 28 145], ...
        'Box', 'on');
    styleAppAxes(app.PlateAxes, theme, 'Plate region preview');

    app.BinaryCard = uipanel(mainPanel, ...
        'Title', 'Segmentation Preview', ...
        'Position', [rightLeft 15 rightWidth 185], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    app.BinaryAxes = uiaxes(app.BinaryCard, ...
        'Position', [14 14 rightWidth - 28 140], ...
        'Box', 'on');
    styleAppAxes(app.BinaryAxes, theme, 'Segmentation preview');

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
            showImageInAxes(currentApp.MainAxes, currentApp.OriginalImage, currentApp.Theme, 'Vehicle image');
            resetAxesPlaceholder(currentApp.PlateAxes, currentApp.Theme, 'Plate region preview');
            resetAxesPlaceholder(currentApp.BinaryAxes, currentApp.Theme, 'Segmentation preview');

            currentApp.PathLabel.Text = ['Source image: ' selectedPath];
            currentApp.StatusLabel.Text = 'Status: image loaded, ready to scan';
            currentApp.ResultValue.Text = 'READY';
            currentApp.ResultValue.FontColor = currentApp.Theme.TitleColor;
            currentApp.ResultHint.Text = 'Press Scan Plate to extract the registration number.';
            currentApp.ClassificationValue.Text = '—';
            currentApp.ClassificationValue.FontColor = currentApp.Theme.AccentSoftColor;
            currentApp.ClassificationText.Value = { ...
                'Plate category, family, and registration group will appear here.', ...
                'Press Scan Plate to begin recognition.'};
            currentApp.ExtractButton.Enable = 'on';
            currentApp.ReportButton.Enable = 'off';
            currentApp.ExportReportButton.Enable = 'off';
        catch readError
            currentApp.StatusLabel.Text = 'Status: unable to open image';
            currentApp.ResultValue.Text = 'LOAD FAILED';
            currentApp.ResultValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ResultHint.Text = 'Verify the selected file and try again.';
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
        currentApp.StatusLabel.Text = 'Status: scanning plate...';
        extractOptions = struct('Mode', "full", 'IncludeDebug', true, 'IncludeV4', true);
        currentApp.ResultValue.Text = 'SCANNING';
        currentApp.ResultValue.FontColor = currentApp.Theme.AccentColor;
        currentApp.ResultHint.Text = 'Processing the image and validating the registration number...';
        currentApp.ExtractButton.Enable = 'off';
        currentApp.ReportButton.Enable = 'off';
        currentApp.ExportReportButton.Enable = 'off';
        guidata(fig, currentApp);
        drawnow limitrate nocallbacks;

        progressDialog = uiprogressdlg(fig, ...
            'Title', 'Scanning Plate', ...
            'Message', 'Analyzing the vehicle image...', ...
            'Indeterminate', 'on', ...
            'Cancelable', 'off');
        warningState = warning('off', 'all');
        warningCleanup = onCleanup(@() warning(warningState));

        try
            result = extractCarPlateFromImage(char(currentApp.ImagePath), extractOptions);
            if ~isvalid(fig)
                return;
            end
            currentApp = guidata(fig);
            currentApp.Result = result;
            showDetectionResult(currentApp, result);
            currentApp.StatusLabel.Text = 'Status: scan complete';
            if hasDetailedReport(result)
                currentApp.ReportButton.Enable = 'on';
                currentApp.ExportReportButton.Enable = 'on';
            end
        catch extractionError
            currentApp.StatusLabel.Text = 'Status: scan failed';
            currentApp.ResultValue.Text = 'FAILED';
            currentApp.ResultValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ResultHint.Text = 'No registration number could be extracted from this image.';
            currentApp.ClassificationValue.Text = 'Unavailable';
            currentApp.ClassificationValue.FontColor = currentApp.Theme.ErrorColor;
            currentApp.ClassificationText.Value = { ...
                'Recognition was not successful.', ...
                ['Error: ' extractionError.message], ...
                'Verify the image quality and try again.'};
            currentApp.ReportButton.Enable = 'off';
            currentApp.ExportReportButton.Enable = 'off';
        end

        if exist('progressDialog', 'var') && isvalid(progressDialog)
            close(progressDialog);
        end

        currentApp.ExtractButton.Enable = 'on';
        currentApp.IsBusy = false;
        guidata(fig, currentApp);
    end

    function onClearView(~, ~)
        currentApp = guidata(fig);
        currentApp.ImagePath = "";
        currentApp.OriginalImage = [];
        currentApp.Result = [];

        cla(currentApp.MainAxes);
        resetAxesPlaceholder(currentApp.MainAxes, currentApp.Theme, 'No image loaded');
        resetAxesPlaceholder(currentApp.PlateAxes, currentApp.Theme, 'Plate region preview');
        resetAxesPlaceholder(currentApp.BinaryAxes, currentApp.Theme, 'Segmentation preview');

        currentApp.PathLabel.Text = 'Source image: none selected';
        currentApp.StatusLabel.Text = 'Status: idle';
        currentApp.ResultValue.Text = '—';
        currentApp.ResultValue.FontColor = currentApp.Theme.TitleColor;
        currentApp.ResultHint.Text = 'The recognized registration number will appear here.';
        currentApp.ClassificationValue.Text = '—';
        currentApp.ClassificationValue.FontColor = currentApp.Theme.AccentSoftColor;
        currentApp.ClassificationText.Value = { ...
            'Plate category, family, and registration group will appear here.', ...
            'Supported categories include civilian, military, diplomatic, special series, and trade plates.'};
        currentApp.ExtractButton.Enable = 'off';
        currentApp.ReportButton.Enable = 'off';
        currentApp.ExportReportButton.Enable = 'off';

        guidata(fig, currentApp);
    end

    function onOpenDetailedReport(~, ~)
        currentApp = guidata(fig);
        if isempty(currentApp.Result) || ~hasDetailedReport(currentApp.Result)
            uialert(fig, 'Scan a plate first to generate the report.', 'Report Unavailable');
            return;
        end

        progressDialog = uiprogressdlg(fig, ...
            'Title', 'Opening Report', ...
            'Message', 'Preparing the detection report...', ...
            'Indeterminate', 'on', ...
            'Cancelable', 'off');
        warningState = warning('off', 'all');
        warningCleanup = onCleanup(@() warning(warningState));
        try
            showDetailedReportWindow(currentApp.Result);
        catch reportError
            warning('PlateReport:OpenFailed', 'Detailed report window failed: %s', reportError.message);
            uialert(fig, sprintf('Unable to open the report.%s%s', ...
                newline, reportError.message), ...
                'Report Error', 'Icon', 'warning');
        end
        if isvalid(progressDialog)
            close(progressDialog);
        end
    end

    function onExportDetailedReport(~, ~)
        currentApp = guidata(fig);
        if isfield(currentApp, 'IsBusy') && currentApp.IsBusy
            return;
        end
        if isempty(currentApp.Result) || ~hasDetailedReport(currentApp.Result)
            uialert(fig, 'Scan a plate first to generate the report.', 'Report Unavailable');
            return;
        end

        currentApp.IsBusy = true;
        currentApp.ExportReportButton.Enable = 'off';
        guidata(fig, currentApp);
        drawnow limitrate nocallbacks;

        progressDialog = uiprogressdlg(fig, ...
            'Title', 'Exporting Report', ...
            'Message', 'Generating the report PDF and supporting images...', ...
            'Indeterminate', 'on', ...
            'Cancelable', 'off');
        warningState = warning('off', 'all');
        warningCleanup = onCleanup(@() warning(warningState));

        try
            exportFolder = exportDetailedReport(currentApp.Result);
            uialert(fig, sprintf('Report saved to:%s%s', newline, exportFolder), ...
                'Report Saved', 'Icon', 'success');
        catch exportError
            warning('PlateReport:ExportFailed', 'Detailed report export failed: %s', exportError.message);
            try
                fallbackFolder = exportDetailedReportFallback(currentApp.Result);
                uialert(fig, sprintf(['The PDF could not be generated.%s%s%s' ...
                    'A text-only report has been saved to:%s%s'], ...
                    newline, exportError.message, newline, newline, fallbackFolder), ...
                    'Report Saved (Text Only)', 'Icon', 'warning');
            catch fallbackError
                warning('PlateReport:BackupExportFailed', ...
                    'Backup report export failed: %s', fallbackError.message);
                uialert(fig, sprintf(['The report could not be saved.%s%s%s' ...
                    'The text-only backup also failed:%s%s'], ...
                    newline, exportError.message, newline, newline, fallbackError.message), ...
                    'Report Save Error', 'Icon', 'error');
            end
        end

        if exist('progressDialog', 'var') && isvalid(progressDialog)
            close(progressDialog);
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
    mainTitle = 'Vehicle image';
    if ~isempty(result.PlateBox) && result.IsPlateTextValid
        mainTitle = ['Recognized plate: ' char(result.PlateText)];
    elseif ~isempty(result.PlateBox)
        mainTitle = 'Plate region detected';
    elseif ~isempty(result.CandidateBoxes)
        mainTitle = 'No reliable plate located';
    end
    showImageInAxes(app.MainAxes, buildAnnotatedMainImage(result), theme, mainTitle);

    if ~isempty(result.PlateImage)
        showImageInAxes(app.PlateAxes, result.PlateImage, theme, 'Plate region preview');
    else
        resetAxesPlaceholder(app.PlateAxes, theme, 'Plate region preview');
    end

    if ~isempty(result.BinaryPlate)
        showImageInAxes(app.BinaryAxes, result.BinaryPlate, theme, 'Segmentation preview');
    else
        resetAxesPlaceholder(app.BinaryAxes, theme, 'Segmentation preview');
    end

    if result.IsPlateTextValid
        app.ResultValue.Text = char(result.PlateText);
        app.ResultValue.FontColor = theme.SuccessColor;
        app.ResultHint.Text = 'Registration number recognized.';
    elseif ~isempty(result.PlateBox)
        app.ResultValue.Text = 'REVIEW REQUIRED';
        app.ResultValue.FontColor = theme.WarningColor;
        if strlength(result.PlateText) > 0
            app.ResultHint.Text = 'A plate region was located, but the recognized text is not reliable enough for acceptance.';
        else
            app.ResultHint.Text = 'A plate region was located, but the registration number could not be recognized.';
        end
    else
        app.ResultValue.Text = 'NO MATCH';
        app.ResultValue.FontColor = theme.ErrorColor;
        app.ResultHint.Text = 'No registration plate could be located in this image.';
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
    cardWidth = 1220;

    selectedAttempt = pickSelectedAttempt(report);
    if isempty(selectedAttempt)
        uifigure( ...
            'Name', 'License Plate Detection Report', ...
            'Position', [80 60 windowWidth windowHeight], ...
            'Color', theme.FigureColor);
        return;
    end

    stepCount = numel(selectedAttempt.Steps);
    stepRows = max(1, ceil(stepCount / 2));
    cardHeight = 120 + stepRows * 290;
    canvasHeight = max(820, 90 + cardHeight + 30);

    reportFigure = uifigure( ...
        'Name', 'License Plate Detection Report', ...
        'Position', [80 60 windowWidth windowHeight], ...
        'Color', theme.FigureColor);

    scrollPanel = uipanel(reportFigure, ...
        'Position', [0 0 windowWidth windowHeight], ...
        'BorderType', 'none', ...
        'BackgroundColor', theme.FigureColor, ...
        'Scrollable', 'on');

    plateText = char(string(result.PlateText));
    if isempty(plateText)
        plateText = '—';
    end
    headerText = sprintf('License Plate Detection Report  |  Recognized Plate: %s', plateText);
    uilabel(scrollPanel, ...
        'Position', [20 canvasHeight - 48 1200 28], ...
        'Text', headerText, ...
        'FontSize', 16, ...
        'FontWeight', 'bold', ...
        'FontColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    yTop = canvasHeight - 80;
    card = uipanel(scrollPanel, ...
        'Title', 'Processing Steps', ...
        'Position', [20 yTop - cardHeight cardWidth cardHeight], ...
        'FontWeight', 'bold', ...
        'BackgroundColor', theme.CardColor, ...
        'ForegroundColor', theme.TitleColor, ...
        'FontName', theme.LabelFont);

    notesText = sanitizeReportNotes(selectedAttempt.Notes);

    uilabel(card, ...
        'Position', [14 cardHeight - 48 cardWidth - 28 28], ...
        'Text', notesText, ...
        'FontSize', 12, ...
        'FontColor', theme.SubtleTextColor, ...
        'FontName', theme.BodyFont);

    for stepIndex = 1:stepCount
        currentStep = selectedAttempt.Steps(stepIndex);
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
            'Value', {'No intermediate steps were recorded.'}, ...
            'FontSize', 12, ...
            'BackgroundColor', theme.CardColor, ...
            'FontColor', theme.BodyTextColor, ...
            'FontName', theme.BodyFont);
    end
end

function selectedAttempt = pickSelectedAttempt(report)
    selectedAttempt = [];
    if ~isstruct(report) || ~isfield(report, 'Attempts') || isempty(report.Attempts)
        return;
    end
    selectedName = "";
    if isfield(report, 'SelectedMethod')
        selectedName = string(report.SelectedMethod);
    end
    for i = 1:numel(report.Attempts)
        attempt = report.Attempts(i);
        if isfield(attempt, 'Method') && ...
                strcmpi(char(string(attempt.Method)), char(selectedName))
            selectedAttempt = attempt;
            return;
        end
    end
    selectedAttempt = report.Attempts(end);
end

function notesText = sanitizeReportNotes(rawNotes)
    rawText = char(string(rawNotes));
    defaultText = 'License plate recognition completed successfully.';

    if isempty(strtrim(rawText))
        notesText = defaultText;
        return;
    end

    sentences = regexp(rawText, '[^.!?]+[.!?]?', 'match');
    if isempty(sentences)
        sentences = {rawText};
    end

    cleanedSentences = strings(0, 1);
    for i = 1:numel(sentences)
        sentence = strtrim(sentences{i});
        if isempty(sentence)
            continue;
        end
        if ~isempty(regexpi(sentence, '\bv[1-4]\b', 'once')) || ...
                ~isempty(regexpi(sentence, 'fallback', 'once'))
            continue;
        end
        sentence = regexprep(sentence, '\bdetector\b', 'recognition engine', 'ignorecase');
        sentence = regexprep(sentence, '\bmethod\b', 'pipeline', 'ignorecase');
        cleanedSentences(end + 1, 1) = string(sentence); %#ok<AGROW>
    end

    if isempty(cleanedSentences)
        notesText = defaultText;
        return;
    end

    notesText = char(strjoin(cleanedSentences, ' '));
    notesText = regexprep(notesText, '\s+', ' ');
    notesText = strtrim(notesText);
    if isempty(notesText)
        notesText = defaultText;
    end
end

function exportFolder = exportDetailedReport(result)
    selectedAttempt = pickSelectedAttempt(result.DebugReport);
    if isempty(selectedAttempt)
        error('PlateReport:NoAttempt', 'No detection steps available to export.');
    end

    reportRoot = fullfile(getDefaultDownloadsFolder(), 'PlateReports');
    if ~isfolder(reportRoot)
        mkdir(reportRoot);
    end

    timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    exportFolder = fullfile(reportRoot, ['PlateReport_' char(timestamp)]);
    mkdir(exportFolder);

    try
        exportSelectedAttemptPDF(result, selectedAttempt, exportFolder);
    catch exportError
        warning('PlateReport:CombinedExportFailed', ...
            'Report export failed: %s', exportError.message);
        rethrow(exportError);
    end

    writeAttemptFallbackSummary(selectedAttempt, exportFolder, []);
end

function exportFolder = exportDetailedReportFallback(result)
    selectedAttempt = pickSelectedAttempt(result.DebugReport);
    if isempty(selectedAttempt)
        error('PlateReport:NoAttempt', 'No detection steps available to export.');
    end

    reportRoot = fullfile(getDefaultDownloadsFolder(), 'PlateReports');
    if ~isfolder(reportRoot)
        mkdir(reportRoot);
    end

    timestamp = string(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
    exportFolder = fullfile(reportRoot, ['PlateReport_Simple_' char(timestamp)]);
    mkdir(exportFolder);

    writeAttemptFallbackSummary(selectedAttempt, exportFolder, []);
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

function exportSelectedAttemptPDF(result, attempt, exportFolder)
    pdfPath = fullfile(exportFolder, 'plate_report.pdf');
    if isfile(pdfPath)
        delete(pdfPath);
    end

    coverFigure = buildCoverFigure(result, attempt);
    cleanupCover = onCleanup(@() close(coverFigure)); %#ok<NASGU>
    exportgraphics(coverFigure, pdfPath, 'ContentType', 'image');

    attemptFigure = buildAttemptReportFigure(attempt);
    cleanupAttempt = onCleanup(@() close(attemptFigure)); %#ok<NASGU>
    exportgraphics(attemptFigure, pdfPath, 'ContentType', 'image', 'Append', true);
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

    notesText = sanitizeReportNotes(attempt.Notes);

    annotation(exportFigure, 'textbox', [0.02 0.965 0.96 0.03], ...
        'String', 'Processing Steps', ...
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
            text(ax, 0.5, 0.5, sprintf('No image for Step %d', stepIndex), ...
                'HorizontalAlignment', 'center', 'Units', 'normalized', ...
                'Color', [0.25 0.25 0.25], 'FontSize', 11);
        end

        title(ax, char(string(currentStep.Title)), 'Interpreter', 'none', 'FontSize', 11);
        descText = char(string(currentStep.Description));
        if strlength(string(currentStep.Description)) == 0
            descText = 'No description.';
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

function exportFigure = buildCoverFigure(result, attempt)
    exportFigure = figure( ...
        'Visible', 'off', ...
        'Color', [1 1 1], ...
        'Position', [100 100 1200 900], ...
        'PaperPositionMode', 'auto', ...
        'InvertHardcopy', 'off');

    plateText = char(string(result.PlateText));
    if isempty(plateText)
        plateText = '—';
    end

    annotation(exportFigure, 'textbox', [0.05 0.92 0.90 0.05], ...
        'String', 'License Plate Detection Report', ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 22, ...
        'Interpreter', 'none', 'Color', [0.10 0.12 0.16]);
    annotation(exportFigure, 'textbox', [0.05 0.86 0.90 0.05], ...
        'String', sprintf('Recognized Plate: %s', plateText), ...
        'EdgeColor', 'none', 'FontWeight', 'bold', 'FontSize', 18, ...
        'Interpreter', 'none', 'Color', [0.18 0.20 0.24]);

    plateClass = classifyMalaysianPlate(result.PlateText);
    annotation(exportFigure, 'textbox', [0.05 0.78 0.90 0.05], ...
        'String', sprintf('Category: %s', char(string(plateClass.Category))), ...
        'EdgeColor', 'none', 'FontSize', 14, ...
        'Interpreter', 'none', 'Color', [0.18 0.20 0.24]);
    annotation(exportFigure, 'textbox', [0.05 0.74 0.90 0.05], ...
        'String', sprintf('Family: %s', plateClass.Family), ...
        'EdgeColor', 'none', 'FontSize', 12, ...
        'Interpreter', 'none', 'Color', [0.36 0.40 0.46]);
    annotation(exportFigure, 'textbox', [0.05 0.70 0.90 0.05], ...
        'String', sprintf('Registration Group: %s', plateClass.Group), ...
        'EdgeColor', 'none', 'FontSize', 12, ...
        'Interpreter', 'none', 'Color', [0.36 0.40 0.46]);

    notesText = sanitizeReportNotes(attempt.Notes);
    annotation(exportFigure, 'textbox', [0.05 0.55 0.90 0.12], ...
        'String', sprintf('Summary:\n%s', notesText), ...
        'EdgeColor', [0.82 0.84 0.88], ...
        'BackgroundColor', [0.98 0.98 0.99], ...
        'FontSize', 11, ...
        'Interpreter', 'none', ...
        'Color', [0.18 0.20 0.24]);

    annotation(exportFigure, 'textbox', [0.05 0.05 0.90 0.06], ...
        'String', 'The following page contains the intermediate processing steps used to recognize this plate.', ...
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

function writeAttemptFallbackSummary(attempt, exportFolder, exportError)
    summaryPath = fullfile(exportFolder, 'plate_report.txt');
    fid = fopen(summaryPath, 'w');
    if fid == -1
        return;
    end
    cleanupFile = onCleanup(@() fclose(fid));

    fprintf(fid, 'Status: %s\n', char(string(attempt.Status)));
    fprintf(fid, 'Notes: %s\n', sanitizeReportNotes(attempt.Notes));
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
