%% Optimized Malaysian Car Plate Detection with OCR

% Step 1: Load the image
img = imread('C:\APU\Matlab\Assignment\DataSet\images\619987432_1308615051304184_1344641544557139936_n.jpg');

% Step 2: Convert to grayscale
grayImg = rgb2gray(img);

% Step 3: Enhance contrast
enhancedImg = imadjust(grayImg);

% Step 4: Apply Gaussian filter to reduce noise
filteredImg = imgaussfilt(enhancedImg, 2);  % sigma = 2

% Step 5: Edge detection (Canny)
edges = edge(filteredImg, 'Canny', [0.1 0.3]);  % thresholds may need tuning

% Step 6: Morphological operations to emphasize horizontal rectangles
se = strel('rectangle', [3 15]);  % horizontal rectangle
morphImg = imdilate(edges, se);
morphImg = imerode(morphImg, se);

% Step 7: Label connected components
cc = bwconncomp(morphImg);
stats = regionprops(cc, 'BoundingBox', 'Area', 'Extent');

% Step 8: Filter candidates based on aspect ratio, area, and extent
figure; imshow(img); hold on;
ocrResults = {};  % Store OCR results

for i = 1:length(stats)
    bbox = stats(i).BoundingBox;
    aspectRatio = bbox(3)/bbox(4);  % Width / Height
    area = stats(i).Area;
    extent = stats(i).Extent;
    
    % Malaysian plates are rectangular and wide
    if aspectRatio > 3 && aspectRatio < 5 && area > 2000 && extent > 0.5
        rectangle('Position', bbox, 'EdgeColor', 'r', 'LineWidth', 2);
        
        % Step 9: Crop candidate region
        plateImg = imcrop(grayImg, bbox);
        
        % Step 10: Adaptive binarization for OCR
        plateImg = imbinarize(plateImg, 'adaptive', 'ForegroundPolarity','dark','Sensitivity',0.4);
        
        % Step 11: OCR on the candidate region
        ocrResult = ocr(plateImg);  
        recognizedText = strtrim(ocrResult.Text);
        ocrResults{end+1} = recognizedText;
        
        % Display OCR result on figure
        text(bbox(1), bbox(2)-10, recognizedText, 'Color', 'yellow', 'FontSize', 12, 'FontWeight', 'bold');
    end
end

title('Detected Malaysian Car Plates with OCR');
hold off;

% Display OCR results in Command Window
disp('Recognized Malaysian Car Plate(s):');
disp(ocrResults);