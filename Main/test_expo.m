%% ======================= Full OCR Pipeline Using helperDetectTextRegions =======================

%% Step 1: Load the image
img = imread('C:\APU\Matlab\Assignment\DataSet\images\619987432_1308615051304184_1344641544557139936_n.jpg');
grayImg = rgb2gray(img);

%% Step 2: Detect text regions using helperDetectTextRegions
params.MinArea = 20;             % minimum pixel area of text blobs
params.MinAspectRatio = 0.062;   % minimum width/height ratio
params.MaxAspectRatio = 4;       % maximum width/height ratio

bboxes = helperDetectTextRegions(grayImg, params);

% Show detected text regions
figure; imshow(img); hold on;
showShape("rectangle", bboxes);
title('Detected Text Regions');

%% Step 3: Initialize OCR results storage
allDetectedText = "";

%% Step 4: Loop over each text region, preprocess, and OCR
for k = 1:size(bboxes,1)
    regionBox = bboxes(k,:);
    
    % Crop the text region
    textRegion = imcrop(img, regionBox);
    grayRegion = rgb2gray(textRegion);
    
    % Step 4a: Reduce reflected light (bright spots)
    reflectionMask = grayRegion > 230;
    medianFiltered = medfilt2(grayRegion, [3 3]);
    grayRegion(reflectionMask) = medianFiltered(reflectionMask);
    
    % Step 4b: Adaptive contrast enhancement
    enhancedRegion = adapthisteq(grayRegion);
    
    % Step 4c: Noise reduction
    filteredRegion = medfilt2(enhancedRegion, [3 3]);
    
    % Step 4d: Sharpen edges
    sharpRegion = imsharpen(filteredRegion);
    
    % Step 4e: Adaptive binarization
    bwRegion = imbinarize(sharpRegion, 'adaptive', 'ForegroundPolarity','dark','Sensitivity',0.4);
    
    % Step 4f: Morphological processing
    se = strel('rectangle', [2 2]);
    morphRegion = imclose(bwRegion, se);
    
    % Step 4g: OCR
    ocrResult = ocr(morphRegion);
    allDetectedText = allDetectedText + " " + ocrResult.Text;
    
    % Optional: show each processed region
    figure; imshow(morphRegion); title(['OCR-ready Text Region #' num2str(k)]);
end

%% Step 5: Display all detected text
disp('==== All Detected Text ====');
disp(allDetectedText);

%% Step 6: Save OCR-ready regions (optional)
imwrite(morphRegion, 'C:\APU\Matlab\Assignment\DataSet\images\OCR_ready_last_region.png');
