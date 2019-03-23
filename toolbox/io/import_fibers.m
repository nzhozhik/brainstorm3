function varargout = process_absolute(varargin)
% IMPORT_FIBERS: Import a set of fibers in a Subject of Brainstorm database.
% 
% USAGE: iNewFibers = import_fibers(iSubject, FibersFiles, FileFormat, offset=[])
%        iNewFibers = import_fibers(iSubject)   : Ask user the files to import
%
% INPUT:
%    - iSubject     : Indice of the subject where to import the fibers
%                     If iSubject=0 : import fibers in default subject
%    - FibersFiles  : Cell array of full filenames of the fibers to import (format is autodetected)
%                     => if not specified : files to import are asked to the user
%    - FileFormat   : String representing the file format to import.
%                     Please see in_fibers.m to get the list of supported file formats
%    - N            : Number of points per fiber
%    - isApplyMriOrient: {0,1}
%    - OffsetMri    : (x,y,z) values to add to the coordinates of the fibers before converting it to SCS
%
% OUTPUT:
%    - iNewFibers : Indices of the fibers added in database

% @=============================================================================
% This function is part of the Brainstorm software:
% https://neuroimage.usc.edu/brainstorm
% 
% Copyright (c)2000-2019 University of Southern California & McGill University
% This software is distributed under the terms of the GNU General Public License
% as published by the Free Software Foundation. Further details on the GPLv3
% license can be found at http://www.gnu.org/copyleft/gpl.html.
% 
% FOR RESEARCH PURPOSES ONLY. THE SOFTWARE IS PROVIDED "AS IS," AND THE
% UNIVERSITY OF SOUTHERN CALIFORNIA AND ITS COLLABORATORS DO NOT MAKE ANY
% WARRANTY, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO WARRANTIES OF
% MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE, NOR DO THEY ASSUME ANY
% LIABILITY OR RESPONSIBILITY FOR THE USE OF THIS SOFTWARE.
%
% For more information type "brainstorm license" at command prompt.
% =============================================================================@
%
% Authors: Martin Cousineau, 2019

eval(macro_method);
end

function [iNewFibers, OutputFibersFiles, nFibers] = Import(iSubject, FibersFiles, FileFormat, N, isApplyMriOrient, OffsetMri)
%% ===== PARSE INPUTS =====
% Check command line
if ~isnumeric(iSubject) || (iSubject < 0)
    error('Invalid subject indice.');
end
if (nargin < 3) || isempty(FibersFiles)
    FibersFiles = {};
    FileFormat = [];
else
    if ischar(FibersFiles)
        FibersFiles = {FibersFiles};
    end
    if (nargin == 2) || ((nargin >= 3) && isempty(FileFormat))
        error('When you pass a FibersFiles argument, FileFormat must be defined too.');
    end
end
if nargin < 4
    N = [];
end
if (nargin < 5) || isempty(isApplyMriOrient)
    isApplyMriOrient = [];
end
if (nargin < 6) || isempty(OffsetMri)
    OffsetMri = [];
end
iNewFibers = [];
OutputFibersFiles = {};
nFibers = [];

% Get Protocol information
ProtocolInfo = bst_get('ProtocolInfo');
% Get subject directory
sSubject = bst_get('Subject', iSubject);
subjectSubDir = bst_fileparts(sSubject.FileName);
% Check the presence of the MRI: warning if no MRI
if isempty(sSubject.Anatomy)
    res = java_dialog('confirm', ...
        ['WARNING: To import correctly fiber files, the subject''s MRI is needed.' 10 10 ...
        'Import subject''s MRI now?' 10 10], 'Import fibers');
    if res
        import_mri(iSubject, [], [], 1);
        return
    end
end

if isempty(N)
    res = java_dialog('input', ...
        ['Please specify how many points per imported fibers (default: 100).' 10 10], 'Import fibers', [], '100');
    if res
        N = str2num(res);
    else
        N = 100;
    end
end


%% ===== SELECT FIBER FILES =====
% If fibers files to load are not defined : open a dialog box to select it
if isempty(FibersFiles)
    % Get last used directories and formats
    LastUsedDirs = bst_get('LastUsedDirs');
    DefaultFormats = bst_get('DefaultFormats');
    if isempty(DefaultFormats.FibersIn)
        DefaultFormats.FibersIn = 'TRK';
    end
    % Get Fibers files
    [FibersFiles, FileFormat, FileFilter] = java_getfile( 'open', ...
       'Import fibers...', ...     % Window title
       LastUsedDirs.ImportAnat, ...   % Default directory
       'multiple', 'files', ...      % Selection mode
       bst_get('FileFilters', 'fibers'), ...
       DefaultFormats.FibersIn);
    % If no file was selected: exit
    if isempty(FibersFiles)
        return
    end
    % Save default import directory
    LastUsedDirs.ImportAnat = bst_fileparts(FibersFiles{1});
    bst_set('LastUsedDirs', LastUsedDirs);
    % Save default import format
    DefaultFormats.FibersIn = FileFormat;
    bst_set('DefaultFormats',  DefaultFormats);
end
   

%% ===== APPLY MRI TRANSFORM =====
% Load MRI
if ~isempty(sSubject.Anatomy)
    sMri = bst_memory('LoadMri', sSubject.Anatomy(sSubject.iAnatomy).FileName);
else
    sMri = [];
end
% If user transformation on MRI: ask to apply transformations on fibers
if isempty(isApplyMriOrient) && ~isempty(sMri) && isfield(sMri, 'InitTransf') && ~isempty(sMri.InitTransf)
    isApplyMriOrient = java_dialog('confirm', ['MRI orientation was non-standard and had to be reoriented.' 10 10 ...
                                   'Apply the same transformation to the fibers?' 10 ...
                                   'Default answer is: NO', 10 10], 'Import fibers');
                               
    % Add MRI translation to the OffsetMri variable
    if isApplyMriOrient
        for i = 1:size(sMri.InitTransf,1)
            ttype = sMri.InitTransf{i,1};
            val   = sMri.InitTransf{i,2};
            if strcmpi(ttype, 'vox2ras')
                MyOffsetMri = -val(1:3,4)';
                if isempty(OffsetMri)
                    OffsetMri = MyOffsetMri;
                else
                    OffsetMri = OffsetMri + MyOffsetMri;
                end
            end
        end
    end
else
    isApplyMriOrient = 0;
end


%% ===== LOAD EACH FIBERS =====
% Process all the selected fibers
for iFile = 1:length(FibersFiles)
    FibersFile = FibersFiles{iFile};
    
    % ===== LOAD FIBERS FILE =====
    bst_progress('start', 'Importing fibers', ['Loading file "' FibersFile '"...']);
    % Load fibers
    Fibers = in_fibers(FibersFile, FileFormat, N, sMri, OffsetMri);
    if isempty(Fibers)
        bst_progress('stop');
        return
    end
    
    % ===== INITIALIZE NEW FIBERS =====
    % Get imported base name
    [tmp__, importedBaseName] = bst_fileparts(FibersFile);
    importedBaseName = strrep(importedBaseName, 'fibers_', '');
    importedBaseName = strrep(importedBaseName, '_fibers', '');
    
    % Only one file
    if (length(Fibers) == 1)
        NewFibers = Fibers;
    % Multiple files
    else
        NewFibers = FibConcatenate(Fibers);
        NewFibers.Comment = sprintf('fibers_%dPt_%dF', N, size(NewFibers.Points, 1));
    end

    % ===== APPLY MRI ORIENTATION =====
    if isApplyMriOrient
        % History: Apply MRI transformation
        NewFibers = bst_history('add', NewFibers, 'import', 'Apply transformation that was applied to the MRI volume');
        % Apply MRI transformation
        NewFibers = ApplyMriTransf(sMri.InitTransf, NewFibers);
    end

    % ===== SAVE BST FILE =====
    % History: File name
    NewFibers = bst_history('add', NewFibers, 'import', ['Import from: ' FibersFile]);
    % Produce a default fibers filename
    BstFibersFile = bst_fullfile(ProtocolInfo.SUBJECTS, subjectSubDir, ['tess_fibers_' importedBaseName '.mat']);
    % Make this filename unique
    BstFibersFile = file_unique(BstFibersFile);
    % Save new fibers in Brainstorm format
    bst_save(BstFibersFile, NewFibers, 'v7');

    % ===== UPDATE DATABASE ======
    % Add new fibers to database
    BstFibFileShort = file_short(BstFibersFile);
    iNewFibers(end+1) = db_add_surface(iSubject, BstFibFileShort, NewFibers.Comment);
    % Unload fibers from memory (if this fibers with the same name was previously loaded)
    bst_memory('UnloadSurface', BstFibersFile);
    % Save output filename
    OutputFibersFiles{end+1} = BstFibersFile;
    % Return number of fibers
    nFibers(end+1) = length(NewFibers.Points);
end

% Save database
db_save();
bst_progress('stop');
end   


%% ======================================================================================
%  ===== HELPER FUNCTIONS ===============================================================
%  ======================================================================================
%% ===== APPLY MRI ORIENTATION =====
function sSurf = ApplyMriTransf(MriTransf, sSurf)
    % Convert points matrix to 2D for transformation.
    [pts, shape3d] = Conv3Dto2D(sSurf.Points);
    % Apply step by step all the transformations that have been applied to the MRI
    for i = 1:size(MriTransf,1)
        ttype = MriTransf{i,1};
        val   = MriTransf{i,2};
        switch (ttype)
            case 'flipdim'
                % Detect the dimensions that have constantly negative coordinates
                iDimNeg = find(sum(sign(pts) == -1) == size(pts,1));
                if ~isempty(iDimNeg)
                    pts(:,iDimNeg) = -pts(:,iDimNeg);
                end
                % Flip dimension
                pts(:,val(1)) = val(2)/1000 - pts(:,val(1));
                % Restore initial negative values
                if ~isempty(iDimNeg)
                    pts(:,iDimNeg) = -pts(:,iDimNeg);
                end
            case 'permute'
                pts = pts(:,val);
            case 'vox2ras'
                % Do nothing, applied earlier
        end
    end
    % Report changes in structure
    sSurf.Points = Conv2Dto3D(pts, shape3d);
end


%% ===== CONCATENATE FIBERS FILES =====
function NewFibers = FibConcatenate(Fibers)
    for iFib = 1:length(Fibers)
        if iFib == 1
            NewFibers = Fibers(iFib);
            continue;
        else
            nFibers = size(Fibers(iFib).Points, 2);
            NewFibers.Points(end+1:end+nFibers, :, :) = Fibers(iFib).Points;
            NewFibers.Colors(end+1:end+nFibers, :, :) = Fibers(iFib).Colors;
        end
    end
end


%% ===== CONVERT 3D MATRICES TO 2D IN A REVERSIBLE WAY =====
function [mat2d, shape3d] = Conv3Dto2D(mat3d, iDimToKeep)
    shape3d = size(mat3d);
    nDims = length(shape3d);
    
    if nargin < 2 || isempty(iDimToKeep)
        iDimToKeep = nDims;
    end
    
    iMergeDims = 1:nDims ~= iDimToKeep;
    mat2d = reshape(mat3d, [prod(shape3d(iMergeDims)), shape3d(iDimToKeep)]);
end


%% ===== CONVERT 2D MATRICES BACK TO 3D =====
function mat3d = Conv2Dto3D(mat2d, shape3d)
    mat3d = reshape(mat2d, shape3d);
end


%% ===== ASSIGN FIBERS TO VERTICES =====
function FibMat = AssignToScouts(FibMat, ConnectFile, ScoutCentroids)
    %TODO: nargin < 3, load ScoutCentroids from ConnectFile

    endPoints = FibMat.Points(:, [1,end], :);
    numPoints = size(FibMat.Points, 1);
    closestPts = zeros(numPoints, 2);
    
    bst_progress('start', 'Fibers Connectivity', 'Assigning fibers to scouts of atlas...');
    
    parfor iPt = 1:numPoints
        for iPos = 1:2
            % Compute Euclidean distances:
            distances = sqrt(sum(bst_bsxfun(@minus, squeeze(endPoints(iPt, iPos, :))', ScoutCentroids).^2, 2));
            % Assign points to the vertex with the smallest distance
            [minVal, iMin] = min(distances);
            closestPts(iPt, iPos) = iMin;
        end
        bst_progress('inc', 1);
    end
    
    numSurfaces = length(FibMat.Scouts);
    if numSurfaces <= 1 && isempty(FibMat.Scouts(1).ConnectFile)
        numSurfaces = 0;
    end
    
    FibMat.Scouts(numSurfaces + 1).ConnectFile = ConnectFile;
    FibMat.Scouts(numSurfaces + 1).Assignment = closestPts;
    bst_progress('stop');
end


%% ===== COMPUTE COLOR BASED ON CURVATURE =====
function FibMat = ComputeColor(FibMat)
    nFibers = size(FibMat.Points, 1);
    nPoints = size(FibMat.Points, 2);
    FibMat.Colors = zeros(nFibers, nPoints, 3, 'uint8');
    
    % Compute RGB based on current and next point
    for iPt = 1:nPoints - 1
        r = abs(FibMat.Points(:, iPt, 1) - FibMat.Points(:, iPt+1, 1));
        g = abs(FibMat.Points(:, iPt, 2) - FibMat.Points(:, iPt+1, 2));
        b = abs(FibMat.Points(:, iPt, 3) - FibMat.Points(:, iPt+1, 3));

        norm = sqrt(r .* r + g .* g + b .* b);

        FibMat.Colors(:, iPt, 1) = 255.0 .* r ./ norm;
        FibMat.Colors(:, iPt, 2) = 255.0 .* g ./ norm;
        FibMat.Colors(:, iPt, 3) = 255.0 .* b ./ norm;
    end
    
    % Apply same color to last point
    FibMat.Colors(:, nPoints, 1) = FibMat.Colors(:, nPoints-1, 1);
    FibMat.Colors(:, nPoints, 2) = FibMat.Colors(:, nPoints-1, 2);
    FibMat.Colors(:, nPoints, 3) = FibMat.Colors(:, nPoints-1, 3);
end
