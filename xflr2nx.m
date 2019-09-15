function xflr2nx(varargin)
% XFLR2NX Convert a .xml file from XFLR to a Siemens NX-readable format.
%   XFLR2NX prompts the user to choose a .xml file, and then choose their
%   conversion preferences. It then renders a series of .dat files which
%   are adjusted such as to be imported into Siemens NX, as well as giving
%   an output preview window with graphics and assorted properties.
%
%   When first installed in a folder, run xflr2nx setup to initialise the
%   function. This will create up to 3 folders, 'XML Files', 'XFLR to NX'
%   and 'DAT Files'. You should move the XFLR outputted XML files you wish
%   to convert into the 'XML Files' folder, and all DAT files used in those
%   XML files into 'DAT Files'.
%
%   Now, and any time you add more DAT files, run the command xflr2nx
%   reload to refresh the cache of aerofoils (or leave the auto-reload
%   option turned on.
%
%   To start the program to perform a conversion, once it is set up as
%   above, simply run xflr2nx in the Command Window.

%% == XFLR2NX (c) 2018 by G.Ebberson, T.Glover & B.Marshall ===============
funcVersion = '2.0.0';
% ==== Changelog 14/11/18 2.0.0 ====
% Finalised the bug fixes for version 2, and modified the call stack to
% free up the command window once everything is drawn.
%
% ==== Known Issues ====
% --- Figure windows do not open at a size suitable to the screen they are
%     viewed on, causing issues with progress rendering (especially on Macs
%     with retina display.
%
% ==== Planned Updates ====
% --- Improve 'Fancy Graphics' to include a mesh showing more detailed wing
%     properties.
%
% --- Interface with the NX API to allow end-to-end importing.
%
% ==== Translation Authors ====
% --- Spanish: F.J. Porras-Robles
% --- German: M.L. Riddings
% =========================================================================

%% == MAIN FUNCTION =======================================================

% Initialise global variables.
debug = 0;
dev = 0;
plane = 0;
errorStruct.init = 0;
chosenLengthNum = 0;
chosenMassNum = 0;
paths = {};
config = {};
pref = {};
rowH = 15;
comp = 0;
xmlPath = 0;
configChanged = 0;
prefChanged = 0;

% Check compatibility.
if verLessThan('matlab','9.5')
    release = version('-release');
    warning('MATLAB R2018b is the supported version. This is %s, all functionality may not be supported.',release);
    comp = 1;
end

% Setup folders.
[paths.root,~,~] = fileparts(mfilename('fullpath'));
paths.res = fullfile(paths.root,'files',filesep);
paths.con = fullfile(paths.res,'config.mat');
paths.aero = fullfile(paths.res,'aerofoil.mat');
if exist(fullfile(paths.res,'lang.mat'),'file')
    paths.lang = fullfile(paths.res,'lang.mat');
else
    paths.lang = fullfile(paths.root,'lang.mat');
end

% If the encoding is not UTF-8, some languages fail.
try
    enc = feature('DefaultCharacterSet');
    if ~strcmp(enc,'UTF-8')
        feature('DefaultCharacterSet','UTF-8');
    end
catch
    warning('Could not set default character set. Some features may be unavailable.')
end

% If the config file exists, use it.
if exist(paths.con,'file')
    load(paths.con,'config','pref');
else
    % If no config file found, use system language.
    pref.lang = get(0,'language');
    pref.installLang = pref.lang;
end

% Load the languages list.
try
    load(paths.lang,'list');
catch
    try
        load(fullfile(paths.root,'lang.mat'),'list');
    catch
        error('xflr2nx:main:langMissing','The lang.mat file is missing.');
    end
end
% Set the localisation to the language file.
localisation.lang = pref.lang;
% If lang does not exist in the list of languages, use en_GB.
if ~any(strcmp(list,pref.lang))
    warning('Error loading language %s, the language file is incomplete or corrupted.\n Using en_GB instead.',localisation.lang)
    localisation.lang = 'en_GB';
    pref.lang = 'en_GB';
    save(fullfile(paths.root,'config.mat'),'pref','-append');
end

% Load the locale language files.
localisation.locale = load(paths.lang,localisation.lang);
% Reset the localisation variable to clean up extra fields.
localisation = localisation.locale.(localisation.lang);
% Set the localisation folder names to the root folder names, as these were
% used in setup.
installLangFiles = load(paths.lang,pref.installLang);
localisation.folder = installLangFiles.(pref.installLang).folder;

% Create path variables.
paths.dat = fullfile(paths.root,localisation.folder.dat,filesep);
paths.xml = fullfile(paths.root,localisation.folder.xml,filesep);
paths.out = fullfile(paths.root,localisation.folder.out,filesep);

if ~ispc
    warning(localisation.warning.notWindows)
end

% Command form handling.
try
    if nargin > 0
        commandList = varargin;
        cont = CommandHandler(commandList);
        if ~cont
            return
        end
    end
    
    % Load key variables.
    load(paths.aero,'aerofoilList')
    load(paths.con,'config','pref');
    
    % Global graphics properties
    graphics.screenSize = get(0,'Screensize');
    figW = graphics.screenSize(3) * pref.defaultW;
    figH = graphics.screenSize(4) * pref.defaultH;
    if comp
        figureX = graphics.screenSize(3)/2 - figW/2;
        figureY = graphics.screenSize(4)/2 - figH/2;
        figureWidth = figW;
        figureHeight = figH;
        rootFolder = paths.root;
        
    end
    
    % Debug and developer.
    if debug && dev && config.devWarn
        warning('%s','Developer mode enabled. Features may be unstable.');
    elseif debug && ~dev && config.debugWarn
        warning('%s',localisation.warning.debugging);
    end
    
    % Run the GUI to get the XML file, and unit preference.
    if config.showUI
        if comp
            GetXmlGuiLeg;
        else
            DrawXmlGui;
        end
    end
    
catch ME
    % If the GUI is still open, close it.
    if exist('graphics','var') && isfield(graphics,'f')
        close(graphics.f)
    end
    if exist('graphics','var') && isfield(graphics,'f2')
        close(graphics.f2)
    end
    % If the error is defined, throw the custom message. If not, return the
    % unknown error string.
    if strcmp(ME.identifier(1:7),'xflr2nx')
        error(errorStruct);
    elseif debug
        rethrow(ME)
    else
        lastME = ME;
        save(paths.con,'lastME','-append');
        error('An unknown error occurred.')
    end
end

%% == NESTED FUNCTIONS ====================================================

    function goodName = NameTidy2(badName)
        intName = badName;
        intName(~ismember(intName,'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz1234567890_ ')) = [];
        intName(intName == ' ') = '_';
        if ismember(intName(1),'0123456789')
            intName = ['a',intName];
        end
        goodName = intName;
    end

    function UnpackPlane(inPlane)
        
        % explane{1,1} appears unused every time.
        unused = inPlane.explane{1,1};
        if ~isempty(unused.Text)
            warning('xflr2nx:UnpackPlane:explaneOneUsed %s',localisation.warning.explaneOneUsed)
        end
        
        % Define intermediate.
        intPlane = inPlane.explane{1,2};
        
        % ==Attributes==
        if ~strcmp(intPlane.Attributes.version,'1.0')
            warning('%s %f %s',localisation.warning.version1,intPlane.Attributes.version,localisation.warning.version2);
        else
            outPlane.version = intPlane.Attributes.version;
        end
        
        % ==Units==
        outPlane.units.length = str2double(intPlane.Units.lengthu_unitu_tou_meter.Text);
        outPlane.units.mass = str2double(intPlane.Units.massu_unitu_tou_kg.Text);
        
        % Sort out unit conversions.
        lengthFactor = outPlane.units.length * localisation.units.lengthFactors{ismember(localisation.units.lengthNames,pref.lengthUnits)};
        massFactor = outPlane.units.mass * localisation.units.massFactors{ismember(localisation.units.massNames,pref.massUnits)};
        
        % ==Plane==
        % Name
        if ~isempty(intPlane.Plane.Name.Text)
            outPlane.name = intPlane.Plane.Name.Text;
        end
        % Description
        if ~isempty(intPlane.Plane.Description.Text)
            outPlane.description = intPlane.Plane.Description.Text;
        end
        % Has Body
        outPlane.hasBody = TrueFalse(intPlane.Plane.hasu_body.Text);
        % Inertia
        if ~isfield(intPlane.Plane.Inertia,'Text')
            if isfield(intPlane.Plane.Inertia,'Pointu_Mass')
                pointMassesIn = intPlane.Plane.Inertia.Pointu_Mass;
                if length(pointMassesIn) == 1
                    pointMasses{1} = pointMassesIn;
                else
                    pointMasses = pointMassesIn;
                end
                for i = 1:length(pointMasses)
                    outPlane.inertia.pointMasses{i}.tag = pointMasses{i}.Tag.Text;
                    outPlane.inertia.pointMasses{i}.mass = str2double(pointMasses{i}.Mass.Text) * massFactor;
                    newCoords = pointMasses{i}.coordinates.Text(pointMasses{i}.coordinates.Text ~= ' ');
                    outPlane.inertia.pointMasses{i}.coords = sscanf(sprintf('%s,',newCoords),'%f,')';
                end
            end
        end
        % Wing
        if isfield(intPlane.Plane,'wing')
            if ~isfield(intPlane.Plane.wing,'Text')
                if length(intPlane.Plane.wing) == 1
                    thisWing{1} = intPlane.Plane.wing;
                else
                    thisWing = intPlane.Plane.wing;
                end
                for i = 1:length(intPlane.Plane.wing)
                    outPlane.wing{i}.name = thisWing{i}.Name.Text;
                    outPlane.wing{i}.type = thisWing{i}.Type.Text;
                    outPlane.wing{i}.description = thisWing{i}.Description.Text;
                    outPlane.wing{i}.symmetric = TrueFalse(thisWing{i}.Symetric.Text);
                    outPlane.wing{i}.isFin = TrueFalse(thisWing{i}.isFin.Text);
                    outPlane.wing{i}.isDoubleFin = TrueFalse(thisWing{i}.isDoubleFin.Text);
                    outPlane.wing{i}.isSymFin = TrueFalse(thisWing{i}.isSymFin.Text);
                    outPlane.wing{i}.colour = [str2double(thisWing{i}.Color.red.Text),str2double(thisWing{i}.Color.green.Text),str2double(thisWing{i}.Color.blue.Text),str2double(thisWing{i}.Color.alpha.Text)];
                    newPos = thisWing{i}.Position.Text(thisWing{i}.Position.Text ~= ' ');
                    outPlane.wing{i}.position = sscanf(sprintf('%s,',newPos),'%f,') * lengthFactor;
                    outPlane.wing{i}.tiltAngle = str2double(thisWing{i}.Tiltu_angle.Text);
                    outPlane.wing{i}.mass = str2double(thisWing{i}.Inertia.Volumeu_Mass.Text) * massFactor;
                    for j = 1:length(thisWing{i}.Sections.Section)
                        thisSection = thisWing{i}.Sections.Section{j};
                        outPlane.wing{i}.sections(j).yPosition = str2double(thisSection.yu_position.Text) * lengthFactor;
                        outPlane.wing{i}.sections(j).chord = str2double(thisSection.Chord.Text) * lengthFactor;
                        outPlane.wing{i}.sections(j).xOffset = str2double(thisSection.xOffset.Text) * lengthFactor;
                        outPlane.wing{i}.sections(j).dihedral = str2double(thisSection.Dihedral.Text);
                        outPlane.wing{i}.sections(j).twist = str2double(thisSection.Twist.Text) + outPlane.wing{i}.tiltAngle;
                        outPlane.wing{i}.sections(j).xPanels = str2double(thisSection.xu_numberu_ofu_panels.Text);
                        outPlane.wing{i}.sections(j).xPanelDist = lower(thisSection.xu_panelu_distribution.Text);
                        outPlane.wing{i}.sections(j).yPanels = str2double(thisSection.yu_numberu_ofu_panels.Text);
                        outPlane.wing{i}.sections(j).yPanelDist = lower(thisSection.yu_panelu_distribution.Text);
                        outPlane.wing{i}.sections(j).leftFoil = NameTidy(thisSection.Leftu_Sideu_FoilName.Text);
                        outPlane.wing{i}.sections(j).rightFoil = NameTidy(thisSection.Rightu_Sideu_FoilName.Text);
                    end
                end
            end
            
            % Rename wings
            for i = 1:length(outPlane.wing)
                if strcmp(outPlane.wing{i}.type,'MAINWING')
                    outPlane.mainWing = outPlane.wing{i};
                elseif strcmp(outPlane.wing{i}.type,'SECONDWING')
                    outPlane.secondWing = outPlane.wing{i};
                elseif strcmp(outPlane.wing{i}.type,'ELEVATOR')
                    outPlane.elevator = outPlane.wing{i};
                elseif strcmp(outPlane.wing{i}.type,'FIN')
                    outPlane.fin = outPlane.wing{i};
                end
            end
            % Remove 'wing'
            outPlane = rmfield(outPlane,'wing');
        end
        
        function [boolean] = TrueFalse(string)
            if strcmp(string,'true')
                boolean = true;
            else
                boolean = false;
            end
        end
        plane = outPlane;
    end

    function cont = CommandHandler(commandList)
        cont = 0;
        command = commandList{1};
        switch command
            case 'setup'
                Setup;
                
            case 'reload'
                % If reload is called, reload all .dat files
                UpdateDatMatrix;
            case 'debug'
                debug = 1;
                cont = 1;
            case 'silent'
                config.showUI = 0;
                if length(commandList) > 1
                    path = commandList{2};
                    if exist(path,'file') == 2 && strcmp(path(end-3:end),'.xml')
                        xmlPath = path;
                        chosenLengthNum = 1;
                        chosenMassNum = 1;
                        if length(commandList) > 2
                            arguments = commandList(3:end);
                            for argNum = length(arguments)
                                switch arguments{argNum}
                                    case '-s'
                                        shiftSections = 0;
                                    otherwise
                                        errorStruct.identifier = 'xflr2nx:CommandHandler:invalidArgument';
                                        errorStruct.message = sprintf('%s "%s" %s',localisation.error.CommandHandler.invalidArgument1,arguments{argNum},localisation.error.CommandHandler.invalidArgument2);
                                        error(errorStruct)
                                end
                            end
                        else
                            errorStruct.identifier = 'xflr2nx:CommandHandler:noSilentArgument';
                            errorStruct.message = sprintf('%s',localisation.error.CommandHandler.noSilentArgument);
                            error(errorStruct)
                        end
                        cont = 1;
                    end
                else
                    errorStruct.identifier = 'xflr2nx:CommandHandler:noSilentArgument';
                    errorStruct.message = localisation.error.CommandHandler.noSilentArgument;
                    error(errorStruct);
                end
            case 'config'
                if length(commandList) > 1
                    arguments = commandList(2:end);
                    if mod(length(arguments),2) == 0
                        for argNum = 1:2:length(arguments)
                            switch arguments{argNum}
                                case 'lang'
                                    lang = arguments{argNum + 1};
                                    save(paths.con,'lang','-append');
                                case 'autoreload'
                                    autoReload = str2double(arguments{argNum + 1});
                                    save(paths.con,'autoReload','-append');
                                case 'exportall'
                                    exportAll = str2double(arguments{argNum + 1});
                                    exportFile = exportAll;
                                    exportVar = exportAll;
                                    save(paths.con,'exportFile','exportVar','-append');
                                case 'exportfile'
                                    exportFile = str2double(arguments{argNum + 1});
                                    save(paths.con,'exportFile','-append');
                                case 'exportvar'
                                    exportVar = str2double(arguments{argNum + 1});
                                    save(paths.con,'exportVar','-append');
                                case 'devwarn'
                                    devWarn = str2double(arguments{argNum + 1});
                                    save(paths.con,'devWarn','-append');
                                case 'debugwarn'
                                    debugWarn = str2double(arguments{argNum + 1});
                                    save(paths.con,'debugWarn','-append');
                                case 'windowsize'
                                    windowSize = str2num(arguments{argNum + 1});
                                    figureWidth = windowSize(1);
                                    figureHeight = windowSize(2);
                                    save(paths.con,'figureWidth','figureHeight','-append');
                            end
                        end
                    elseif length(arguments) == 1
                        switch arguments{1}
                            case 'help'
                                fprintf('HELP!\n')
                        end
                    end
                end
            case 'dev'
                dev = 1;
                debug = 1;
                cont = 1;
            otherwise
                % Otherwise, return and run normally.
                return
        end
    end

    function aerofoilList = UpdateDatMatrix
        % UPDATEDATMATRIX regenerates the .dat matrix from the DAT Files
        % folder.
        
        % Add the DAT folder to the path, then generate a list of .dat
        % files which are present, to be iterated over.
        if verLessThan('matlab','9.1')
            fileList = FolderList(paths.dat);
        else
            fileList = dir([paths.dat,filesep,'**',filesep,'*.dat']);
        end
        addpath(genpath(paths.dat));
        
        % Iterate over each .dat file, opening it and loading it into the
        % aerofoil matrix.
        aerofoilList = cell(1,length(fileList));
        for fileNum = 1:length(fileList)
            try
                thisFileID = fopen([fileList(fileNum).folder,filesep,fileList(fileNum).name]);
                thisName = textscan(thisFileID,'%s',1,'Delimiter','\n');
                thisPoints = textscan(thisFileID,'%f %f');
                if thisPoints{1}(1) == round(thisPoints{1}(1)) && thisPoints{1}(1) > 1
                    aerofoilList{fileNum}.numPoints = [thisPoints{1}(1),thisPoints{2}(1)];
                    thisPoints{1}(1:2) = [];
                    thisPoints{2}(1:2) = [];
                    aerofoilList{fileNum}.format = 'Lednicer';
                    aerofoilList{fileNum}.coords = [thisPoints{1}(1:(aerofoilList{fileNum}.numPoints(1)-1)),thisPoints{2}(1:(aerofoilList{fileNum}.numPoints(2)-1));flipud(thisPoints{1}(aerofoilList{fileNum}.numPoints(1):end)),flipud(thisPoints{2}(aerofoilList{fileNum}.numPoints(2):end))];
                elseif round(thisPoints{1}(1),2) == 1
                    aerofoilList{fileNum}.format = 'Selig';
                    aerofoilList{fileNum}.numPoints = [length(thisPoints{1}),length(thisPoints{1})];
                    aerofoilList{fileNum}.coords = [thisPoints{1},thisPoints{2}];
                else
                    errorStruct.identifier = 'xflr2nx:UpdateDatMatrix:badDatFormat';
                    errorStruct.message = sprintf('%s "%s" %s',localisation.error.UpdateDatMatrix.badDatFormat1,fileList(fileNum).name,localisation.error.UpdateDatMatrix.badDatFormat2);
                    error(errorStruct);
                end
                aerofoilList{fileNum}.name = thisName{1}{1};
                aerofoilList{fileNum}.filename = fileList(fileNum).name;
                aerofoilList{fileNum}.folder = fileList(fileNum).folder;
                fclose(thisFileID);
                DebugLog(sprintf('Loaded file %s successfully...',thisName{1}{1}));
            catch
                fclose(thisFileID);
                errorStruct.identifier = 'xflr2nx:UpdateDatMatrix:badDatFormat';
                errorStruct.message = sprintf('%s "%s" %s',localisation.error.UpdateDatMatrix.badDatFormat1,fileList(fileNum).name,localisation.error.UpdateDatMatrix.badDatFormat2);
                error(errorStruct);
            end
        end
        aerofoilListOut = DatConflictResolver(aerofoilList);
        aerofoilList = aerofoilListOut;
        save(paths.aero,'aerofoilList')
        DebugLog('Saved foil list successfully...');
    end

    function aerofoilListOut = DatConflictResolver(aerofoilListIn)
        aerofoilListOut = {};
        foilNames = cell(length(aerofoilListIn),1);
        for foil = 1:length(aerofoilListIn)
            thisFoil = aerofoilListIn{foil};
            if any(strcmp(foilNames,thisFoil.name))
                otherFoil = aerofoilListIn(ismember(foilNames(1:foil-1),thisFoil.name));
                otherFoil = otherFoil{1};
                % Launch graphic window to resolve conflict.
                if comp
                    DrawConflictGuiLeg(thisFoil,otherFoil);
                else
                    DrawConflictGui(thisFoil,otherFoil);
                end
                uiwait
                return
            else
                foilNames{foil} = thisFoil.name;
                aerofoilListOut{end+1} = thisFoil;
            end
        end
    end

    function outStruct = xml2struct(input)
        %XML2STRUCT converts xml file into a MATLAB structure
        %
        % outStruct = xml2struct2(input)
        %
        % xml2struct2 takes either a java xml object, an xml file, or a string in
        % xml format as input and returns a parsed xml tree in structure.
        %
        % Please note that the following characters are substituted
        % '-' by '_dash_', ':' by '_colon_' and '.' by '_dot_'
        %
        % Originally written by W. Falkena, ASTI, TUDelft, 21-08-2010
        % Attribute parsing speed increase by 40% by A. Wanner, 14-6-2011
        % Added CDATA support by I. Smirnov, 20-3-2012
        % Modified by X. Mo, University of Wisconsin, 12-5-2012
        % Modified by Chao-Yuan Yeh, August 2016
        
        % MIT License
        %
        % Copyright (c) 2016 Joe Yeh
        %
        % Permission is hereby granted, free of charge, to any person obtaining a copy
        % of this software and associated documentation files (the "Software"), to deal
        % in the Software without restriction, including without limitation the rights
        % to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
        % copies of the Software, and to permit persons to whom the Software is
        % furnished to do so, subject to the following conditions:
        %
        % The above copyright notice and this permission notice shall be included in all
        % copies or substantial portions of the Software.
        %
        % THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
        % IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
        % FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
        % AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
        % LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
        % OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
        % SOFTWARE.
        
        
        errorMsg = ['%s is not in a supported format.\n\nInput has to be',...
            ' a java xml object, an xml file, or a string in xml format.'];
        
        % check if input is a java xml object
        if isa(input, 'org.apache.xerces.dom.DeferredDocumentImpl') ||...
                isa(input, 'org.apache.xerces.dom.DeferredElementImpl')
            xDoc = input;
        else
            try
                if exist(input, 'file') == 2
                    xDoc = xmlread(input);
                else
                    try
                        xDoc = xmlFromString(input);
                    catch
                        error(errorMsg, inputname(1));
                    end
                end
            catch ME
                if strcmp(ME.identifier, 'MATLAB:UndefinedFunction')
                    error(errorMsg, inputname(1));
                else
                    rethrow(ME)
                end
            end
        end
        
        % parse xDoc into a MATLAB structure
        outStruct = parseChildNodes(xDoc);
        
        
        function [children, ptext, textflag] = parseChildNodes(theNode)
            % Recurse over node children.
            children = struct;
            ptext = struct;
            textflag = 'Text';
            
            if hasChildNodes(theNode)
                childNodes = getChildNodes(theNode);
                numChildNodes = getLength(childNodes);
                
                for count = 1:numChildNodes
                    
                    theChild = item(childNodes,count-1);
                    [text, name, attr, childs, textflag] = getNodeData(theChild);
                    
                    if ~strcmp(name,'#text') && ~strcmp(name,'#comment') && ...
                            ~strcmp(name,'#cdata_dash_section')
                        % XML allows the same elements to be defined multiple times,
                        % put each in a different cell
                        if (isfield(children,name))
                            if (~iscell(children.(name)))
                                % put existsing element into cell format
                                children.(name) = {children.(name)};
                            end
                            index = length(children.(name))+1;
                            % add new element
                            children.(name){index} = childs;
                            
                            textfields = fieldnames(text);
                            if ~isempty(textfields)
                                for ii = 1:length(textfields)
                                    children.(name){index}.(textfields{ii}) = ...
                                        text.(textfields{ii});
                                end
                            end
                            if(~isempty(attr))
                                children.(name){index}.('Attributes') = attr;
                            end
                        else
                            % add previously unknown (new) element to the structure
                            
                            children.(name) = childs;
                            
                            % add text data ( ptext returned by child node )
                            textfields = fieldnames(text);
                            if ~isempty(textfields)
                                for ii = 1:length(textfields)
                                    children.(name).(textfields{ii}) = text.(textfields{ii});
                                end
                            end
                            
                            if(~isempty(attr))
                                children.(name).('Attributes') = attr;
                            end
                        end
                    else
                        ptextflag = 'Text';
                        if (strcmp(name, '#cdata_dash_section'))
                            ptextflag = 'CDATA';
                        elseif (strcmp(name, '#comment'))
                            ptextflag = 'Comment';
                        end
                        
                        % this is the text in an element (i.e., the parentNode)
                        if (~isempty(regexprep(text.(textflag),'[\s]*','')))
                            if (~isfield(ptext,ptextflag) || isempty(ptext.(ptextflag)))
                                ptext.(ptextflag) = text.(textflag);
                            else
                                % This is what happens when document is like this:
                                % <element>Text <!--Comment--> More text</element>
                                %
                                % text will be appended to existing ptext
                                ptext.(ptextflag) = [ptext.(ptextflag) text.(textflag)];
                            end
                        end
                    end
                    
                end
            end
        end
        
        function [text,name,attr,childs,textflag] = getNodeData(theNode)
            % Create structure of node info.
            
            %make sure name is allowed as structure name
            name = char(getNodeName(theNode));
            name = strrep(name, '-', '_dash_');
            name = strrep(name, ':', '_colon_');
            name = strrep(name, '.', '_dot_');
            name = strrep(name, '_', 'u_');
            
            attr = parseAttributes(theNode);
            if (isempty(fieldnames(attr)))
                attr = [];
            end
            
            %parse child nodes
            [childs, text, textflag] = parseChildNodes(theNode);
            
            % Get data from any childless nodes. This version is faster than below.
            if isempty(fieldnames(childs)) && isempty(fieldnames(text))
                text.(textflag) = char(getTextContent(theNode));
            end
            
            % This alterative to the above 'if' block will also work but very slowly.
            % if any(strcmp(methods(theNode),'getData'))
            %   text.(textflag) = char(getData(theNode));
            % end
            
        end
        
        function attributes = parseAttributes(theNode)
            % Create attributes structure.
            attributes = struct;
            if hasAttributes(theNode)
                theAttributes = getAttributes(theNode);
                numAttributes = getLength(theAttributes);
                
                for count = 1:numAttributes
                    % Suggestion of Adrian Wanner
                    str = char(toString(item(theAttributes,count-1)));
                    k = strfind(str,'=');
                    attr_name = str(1:(k(1)-1));
                    attr_name = strrep(attr_name, '-', '_dash_');
                    attr_name = strrep(attr_name, ':', '_colon_');
                    attr_name = strrep(attr_name, '.', '_dot_');
                    attributes.(attr_name) = str((k(1)+2):(end-1));
                end
            end
        end
        
        function xmlroot = xmlFromString(iString)
            import org.xml.sax.InputSource
            import java.io.*
            
            iSource = InputSource();
            iSource.setCharacterStream(StringReader(iString));
            xmlroot = xmlread(iSource);
        end
        
    end

    function goodName = NameTidy(badName)
        intName = badName;
        intName(regexp(intName,'[<>:"|?*]')) = [];
        if strcmp(intName(end-3:end),'.dat')
            intName(end-3:end) = [];
        end
        if any(regexp(intName,'[\]'))
            slashes = find(intName == '\');
            intName = intName(slashes(end)+1:end);
        elseif any(regexp(intName,'[/]'))
            slashes = find(intName == '/');
            intName = intName(slashes(end)+1:end);
        end
        goodName = intName;
    end

    function WingPlot(m,CData)
        %   Function to plot a symmetrical wing in 3D space.
        %   Takes a cell M containing the co-ordinates of each slice of a wing in
        %   3D space - these co-ordinates must first be processed by ccalc3 or
        %   xflr2nx (eg in correct dimensions and format)
        
        % Length of the input (number of sections).
        secs = length(m);
        
        % Preallocate for speed, since NaN is not plotted.
        m_tr_ed = NaN(secs,3);
        tr_ed = NaN(secs,3);
        m_le_ed = NaN(secs,3);
        le_ed = NaN(secs,3);
        
        ax = graphics.choice.wingPlotAxes;
        
        for n=1:length(m)
            
            % Get this section's data from the input cell.
            out_co_ords=m{n};
            
            % Initialise the plotted coords matrix.
            m_out_co_ords=[out_co_ords(:,1),-out_co_ords(:,2),out_co_ords(:,3)];
            
            % Get the locations of the maximum and minimum points, to connect the
            % leading and trailing edges.
            [~,a] = max(out_co_ords(:,1));
            [~,b] = min(out_co_ords(:,1));
            
            % Coordinates of the trailing edge.
            m_tr_ed(n,:)=(m_out_co_ords(floor(b),:)+m_out_co_ords(ceil(b),:))/2;
            tr_ed(n,:)=(out_co_ords(floor(b),:)+out_co_ords(ceil(b),:))/2;
            
            % Coordinates of the leading edge.
            m_le_ed(n,:)=(m_out_co_ords(floor(a),:)+m_out_co_ords(ceil(a),:))/2;
            le_ed(n,:)=(out_co_ords(floor(a),:)+out_co_ords(ceil(a),:))/2;
            
            % Plot the cross sections.
            
            if ~config.fancyGraphics
                plot3(ax,m_out_co_ords(:,1),m_out_co_ords(:,2),m_out_co_ords(:,3),'-k');
                plot3(ax,out_co_ords(:,1),out_co_ords(:,2),out_co_ords(:,3),'-k');
            else
                fill3(ax,m_out_co_ords(:,1),m_out_co_ords(:,2),m_out_co_ords(:,3),CData);
                fill3(ax,out_co_ords(:,1),out_co_ords(:,2),out_co_ords(:,3),CData);
            end
            
        end
        
        % Add the leading and trailing edges.
        plot3(ax,m_tr_ed(:,1),m_tr_ed(:,2),m_tr_ed(:,3),'k-');
        plot3(ax,m_le_ed(:,1),m_le_ed(:,2),m_le_ed(:,3),'k-');
        plot3(ax,le_ed(:,1),le_ed(:,2),le_ed(:,3),'k-');
        plot3(ax,tr_ed(:,1),tr_ed(:,2),tr_ed(:,3),'k-');
        
    end

    function outFileList = FolderList(folderPath)
        outFileList = {};
        fileList = dir(folderPath);
        for entry = 3:length(fileList)
            if fileList(entry).isdir
                theseFiles = FolderList([folderPath,'\',fileList(entry).name]);
                for file = 1:length(theseFiles)
                    outFileList(end+1).name = theseFiles(file).name;
                    outFileList(end).folder = theseFiles(file).folder;
                    outFileList(end).date = theseFiles(file).date;
                    outFileList(end).bytes = theseFiles(file).bytes;
                    outFileList(end).isdir = theseFiles(file).isdir;
                    outFileList(end).datenum = theseFiles(file).datenum;
                end
                
            else
                outFileList(end+1).name = fileList(entry).name;
                outFileList(end).folder = fileList(entry).folder;
                outFileList(end).date = fileList(entry).date;
                outFileList(end).bytes = fileList(entry).bytes;
                outFileList(end).isdir = fileList(entry).isdir;
                outFileList(end).datenum = fileList(entry).datenum;
            end
        end
    end

    function [sections,name,desc,massStr,spanStr,sizeStr,lines,fName] = PreScanXml(inFile)
        % Get a cell which contains a list of the sections the plane has.
        
        % In case none is found.
        sections = '';
        name = '';
        desc = '';
        massStr = '';
        spanStr = '';
        sizeStr = '';
        lines = 1;
        fName = '';
        
        % Initial calls.
        if comp
            if isempty(inFile) || inFile(end) == filesep
                return
            end
        else
            if isempty(inFile) || inFile(end) == filesep || ~isfile(inFile)
                return
            end
        end
        
        % Get the size.
        loc = cd;
        [fPath,fName,fExt] = fileparts(inFile);
        cd(fPath);
        data = dir([fName,fExt]);
        cd(loc);
        sizeStr = sprintf('%i %s',data.bytes,localisation.gui.bytes);
        
        % Open in simple I/O as it's quickest.
        file = fopen(inFile);
        
        % Get first line.
        thisLine = fgetl(file);
        
        intSections = {};
        foundName = 0;
        foundDescription = 0;
        foundMass = 0;
        intMass = 0;
        massFactor = 0;
        currSemiSpan = 0;
        
        % While line exists, keep checking for type or name.
        while ischar(thisLine)
            thisLine = strtrim(thisLine);
            if strcmp(thisLine(1:6),'<Type>')
                strEnd = find(thisLine == '<',1,'last')-1;
                section = thisLine(7:strEnd);
                if strcmp(section,'MAINWING')
                    intSections{end+1} = 'Main Wing';
                elseif strcmp(section,'SECONDWING')
                    intSections{end+1} = 'Second Wing';
                elseif strcmp(section,'ELEVATOR')
                    intSections{end+1} = 'Elevator';
                elseif strcmp(section,'FIN')
                    intSections{end+1} = 'Fin';
                end
            elseif ~foundName && strcmp(thisLine(1:6),'<Name>')
                strEnd = find(thisLine == '<',1,'last')-1;
                name = thisLine(7:strEnd);
                foundName = 1;
            elseif ~foundDescription && length(thisLine) > 13 && strcmp(thisLine(1:13),'<Description>')
                strEnd = find(thisLine == '<',1,'last')-1;
                desc = thisLine(14:strEnd);
                foundDescription = 1;
            elseif strcmp(thisLine(1:6),'<Mass>')
                strEnd = find(thisLine == '<',1,'last')-1;
                intMass = intMass + str2double(thisLine(7:strEnd));
                foundMass = 1;
            elseif length(thisLine) > 13 && strcmp(thisLine(1:13),'<Volume_Mass>')
                strEnd = find(thisLine == '<',1,'last')-1;
                intMass = intMass + str2double(thisLine(14:strEnd));
                foundMass = 1;
            elseif length(thisLine) > 17 && strcmp(thisLine(1:17),'<mass_unit_to_kg>')
                strEnd = find(thisLine == '<',1,'last')-1;
                massFactor = str2double(thisLine(18:strEnd));
            elseif length(thisLine) > 12 && strcmp(thisLine(1:12),'<y_position>')
                strEnd = find(thisLine == '<',1,'last')-1;
                thisSemiSpan = str2double(thisLine(13:strEnd));
                currSemiSpan(thisSemiSpan > currSemiSpan) = thisSemiSpan;
            elseif length(thisLine) > 22 && strcmp(thisLine(1:22),'<length_unit_to_meter>')
                strEnd = find(thisLine == '<',1,'last')-1;
                lengthFactor = str2double(thisLine(23:strEnd));
            end
            thisLine = fgetl(file);
        end
        
        % Close
        fclose(file);
        
        % Return the sections cell.
        sections = intSections;
        lines = length(sections);
        lines(lines<1) = 1;
        
        if ~foundDescription
            desc = '';
        end
        if ~foundName
            name = '';
        end
        if ~foundMass
            intMass = 0;
        end
        
        mass = massFactor * intMass;
        if mass == 0
            massStr = '';
        elseif log10(mass) < 0
            mass = mass * 1000;
            massStr = sprintf('%.3f %s',mass,'g');
        else
            massStr = sprintf('%.3f %s',mass,'kg');
        end
        
        span = currSemiSpan * 2 * lengthFactor;
        if span == 0
            spanStr = '';
        elseif log10(span) < 0
            span = span * 1000;
            spanStr = sprintf('%.3f %s',span,'mm');
        else
            spanStr = sprintf('%.3f %s',span,'m');
        end
        
    end

    function Process(field)
        
        % Load the data.
        data = plane.(field).sections;
        matrix = [[data.chord]',[data.twist]',[data.xOffset]',[data.dihedral]',[data.yPosition]'];
        DebugLog(sprintf('Loaded %s data for processing successfully...',field));
        
        % Add fin dihedral.
        if strcmp(field,'fin')
            matrix(:,4) = matrix(:,4) + 90;
        end
        
        numSections = size(matrix,1);
        
        % Make the yPositions relative.
        for i = 2:numSections
            for j = 1:i-1
                matrix(i,5) = matrix(i,5) - matrix(i-j,5);
            end
        end
        
        % End dihedral cannot be zero.
        if matrix(end,4) == 0
            matrix(end,4) = matrix(end-1,4);
        end
        
        % Check both wings use same aerofoil.
        if strcmp({data.leftFoil},{data.rightFoil})
            aerofoil = {data.leftFoil}';
        else
            aerofoil = {data.leftFoil;data.rightFoil}';
        end
        
        iCoords = [0,0];
        for i = 1:numSections
            for foil = 1:length(aerofoilList)
                if strcmp(aerofoilList{foil}.name,aerofoil{i})
                    iCoords = aerofoilList{foil}.coords;
                end
            end
            
            % If loop has executed fully without changing data.
            if isequal(iCoords,[0,0])
                errorStruct.identifier = 'xflr2nx:Main:aerofoilMissing';
                errorStruct.message = sprintf('There is no data for %s.',aerofoil{i});
                error(errorStruct);
            end
            
            % Now add third dimension.
            iCoords(:,3) = 0;
            
            % Rotation.
            oCoords = iCoords * matrix(i,1);
            if i == 1 && matrix(i,4) ~= 0     % Inboardmost.
                oCoords = oCoords * rotx(matrix(i,4));
            elseif matrix(i,4) ~= 0           % All others.
                oCoords = oCoords * rotx(matrix(i-1,4));
            end
            
            % Twist.
            if matrix(i,2) ~= 0
                oCoords(:,1) = oCoords(:,1) + (matrix(i,1)/4);
                oCoords(:,1) = cosd(matrix(i,2)).*oCoords(:,1) + sind(matrix(i,2)).*oCoords(:,2);
                oCoords(:,2) = (-sind(matrix(i,2))).*oCoords(:,1) + cosd(matrix(i,2)).*oCoords(:,2);
                oCoords(:,1) = oCoords(:,1) - (matrix(i,1)/4);
            end
            
            % Sweep.
            if matrix(i,3) ~= 0
                oCoords(:,1) = oCoords(:,1) + matrix(i,3);
            end
            
            % Spanwise position.
            if matrix(i,5) ~= 0
                if i == 1 % In case not starting at y = 0.
                    oCoords(:,3) = oCoords(:,3) + matrix(1,5) * cosd(matrix(1,4));
                    oCoords(:,2) = oCoords(:,2) + matrix(1,5) * sind(matrix(1,4));
                else
                    for j=1:i-1 % Add the effect of every section so far.
                        if i-j>0
                            oCoords(:,3)=oCoords(:,3)+(matrix(i-j+1,5)*cosd(matrix(i-j,4)));
                            oCoords(:,2)=oCoords(:,2)+(matrix(i-j+1,5)*sind(matrix(i-j,4)));
                        end
                    end
                end
            end
            
            finalCoords=oCoords(:,[1 3 2]); % Permute to swap axes.
            
            % Apply section shift.
            if config.shiftSections
                finalCoords = finalCoords + plane.(field).position';
            end
            
            % Assign the graphics copy of the wing.
            graphics.(sprintf('%sCoords',field)){i} = finalCoords;
            
            DebugLog(sprintf('Processed %s section %i successfully...',field,i));
            
            % Export the files.
            if config.exportFile
                curDir = cd;
                cd(pref.lastOutputDir)
                outputName = sprintf('%s %i (%s).dat',plane.(field).name,i,aerofoil{i});
                dlmwrite(outputName,finalCoords,'delimiter','\t','newline','pc');
                cd(curDir);
                DebugLog(sprintf('Successfully wrote file %s...',outputName));
            end
        end
    end

    function Process2(field)
        
        % Load the data.
        data = plane.(field).sections;
        matrix = [[data.chord]',[data.twist]',[data.xOffset]',[data.dihedral]',[data.yPosition]'];
        
        % Add fin dihedral.
        if strcmp(field,'fin')
            matrix(:,4) = matrix(:,4) + 90;
        end
        
        numSections = size(matrix,1);
        
        % Make the yPositions relative.
        for i = 2:numSections
            for j = 1:i-1
                matrix(i,5) = matrix(i,5) - matrix(i-j,5);
            end
        end
        
        % End dihedral cannot be zero.
        if matrix(end,4) == 0
            matrix(end,4) = matrix(end-1,4);
        end
        
        % Check both wings use same aerofoil.
        if strcmp({data.leftFoil},{data.rightFoil})
            aerofoil = {data.leftFoil}';
        else
            aerofoil = {data.leftFoil;data.rightFoil}';
        end
        
        iCoords = [0,0];
        for i = 1:numSections
            for foil = 1:length(aerofoilList)
                if strcmp(aerofoilList{foil}.name,aerofoil{i})
                    iCoords = aerofoilList{foil}.coords;
                end
            end
            
            % If loop has executed fully without changing data.
            if isequal(iCoords,[0,0])
                errorStruct.identifier = 'xflr2nx:Main:aerofoilMissing';
                errorStruct.message = sprintf('There is no data for %s.',aerofoil{i});
                error(errorStruct);
            end
            
            % Now add third dimension.
            iCoords(:,3) = 0;
            
            % Rotation.
            oCoords = iCoords * matrix(i,1);
            if i == 1 && matrix(i,4) ~= 0     % Inboardmost.
                oCoords = oCoords * rotx(matrix(i,4));
            elseif matrix(i,4) ~= 0           % All others.
                oCoords = oCoords * rotx(matrix(i-1,4));
            end
            
            % Twist.
            if matrix(i,2) ~= 0
                oCoords(:,1) = oCoords(:,1) + (matrix(i,1)/4);
                oCoords(:,1) = cosd(matrix(i,2)).*oCoords(:,1) + sind(matrix(i,2)).*oCoords(:,2);
                oCoords(:,2) = (-sind(matrix(i,2))).*oCoords(:,1) + cosd(matrix(i,2)).*oCoords(:,2);
                oCoords(:,1) = oCoords(:,1) - (matrix(i,1)/4);
            end
            
            % Sweep.
            if matrix(i,3) ~= 0
                oCoords(:,1) = oCoords(:,1) + matrix(i,3);
            end
            
            % Spanwise position.
            if matrix(i,5) ~= 0
                if i == 1 % In case not starting at y = 0.
                    oCoords(:,3) = oCoords(:,3) + matrix(1,5) * cosd(matrix(1,4));
                    oCoords(:,2) = oCoords(:,2) + matrix(1,5) * sind(matrix(1,4));
                else
                    for j=1:i-1 % Add the effect of every section so far.
                        if i-j>0
                            oCoords(:,3)=oCoords(:,3)+(matrix(i-j+1,5)*cosd(matrix(i-j,4)));
                            oCoords(:,2)=oCoords(:,2)+(matrix(i-j+1,5)*sind(matrix(i-j,4)));
                        end
                    end
                end
            end
            
            finalCoords=oCoords(:,[1 3 2]); % Permute to swap axes.
            
            % Apply section shift.
            if config.shiftSections
                finalCoords = finalCoords + plane.(field).position';
            end
            
            % Assign the graphics copy of the wing.
            graphics.(sprintf('%sCoords',field)){i} = finalCoords;
            
            DebugLog(sprintf('Processed %s section %i successfully...',field,i));
        end
    end

    function Kernel
        
        if xmlPath == 0
            % If window is aborted mid-GUI, exit program.
            return
        elseif ischar(xmlPath)
            [~,xmlName,xmlExt] = fileparts(xmlPath);
            if ~strcmp(xmlExt,'.xml')
                % If file path doesn't end in .xml, throw an error.
                errorStruct.identifier = 'xflr2nx:ChooseXmlGui:notXmlChosen';
                errorStruct.message = localisation.error.ChooseXmlGui.noXmlChosen;
                error(errorStruct);
            end
        end
        DebugLog('XML name is OK...');
        
        % Import and clean up the raw XML structure.
        raw = xml2struct(xmlPath);
        DebugLog('XML imported successfully...');
        UnpackPlane(raw);
        DebugLog('Plane data format converted successfully...');
        
        % Coords storage for graphics.
        graphics.mainWingCoords = {};
        graphics.secondWingCoords = {};
        graphics.elevatorCoords = {};
        graphics.finCoords = {};
        
        % If no sections exist, throw an error.
        partNames = {'mainWing','secondWing','elevator','fin'};
        thisParts = partNames(ismember(partNames,fieldnames(plane)));
        if isempty(thisParts)
            errorStruct.identifier = 'xflr2nx:Main:noWingSections';
            errorStruct.message = localisation.error.Main.noWingSections;
            error(errorStruct);
        end
        DebugLog(sprintf('Sections data identified successfully for %i section(s)...',length(thisParts)));
        
        % Make a new folder for the output files.
        if config.exportFile
            parentDir = fullfile(paths.out,xmlName,filesep);
            if ~exist(parentDir,'dir')
                DebugLog('Parent directory not found. Attempting to make one...');
                mkdir(parentDir);
                DebugLog('Parent directory made successfully...');
            else
                DebugLog('Parent directory found...');
            end
            dateAndTime = datestr(datetime('now'),localisation.dateTimeFormat);
            pref.lastOutputDir = fullfile(parentDir,dateAndTime);
            mkdir(pref.lastOutputDir)
            DebugLog('Output directory made successfully...')
            save(paths.con,'pref','config');
        end
        
        for part = 1:length(thisParts)
            Process(thisParts{part});
        end
        
        DebugLog('Wrote all parts successfully...');
        
        % Tidy up name for output, then assign variable in the base workspace.
        if config.exportVar
            if strcmp(plane.name,'Plane Name')
                varName = xmlName(1:end-3);
            else
                varName = plane.name;
            end
            assignin('base',sprintf(NameTidy2(varName)),plane);
            DebugLog('Wrote the output variable to base workspace successfully...');
        end
        
        DebugLog('Completed Successfully.')
        if debug
            graphics.debug.continue.Enable = 'on';
            uiwait(graphics.f);
        end
        
        % Run the completion GUI.
        if config.showUI
            if comp
                CompleteGuiLeg;
            else
                DrawCompleteGui;
            end
        end
        
    end

    function DebugLog(str)
        if debug && ~comp
            graphics.debug.console.Value{end+1} = str;
        end
    end

    function str = MakeChar(data)
        % Convert data to a string.
        
        cl = class(data);
        
        switch cl
            case 'char'
                str = data;
            case 'double'
                str = mat2str(data);
            case 'logical'
                str = num2str(data);
        end
        
    end

    function Setup
        
        % Perform the setup of folders needed.
        if ~exist(paths.out,'dir')
            mkdir(paths.out);
        end
        if ~exist(paths.dat,'dir')
            mkdir(paths.dat);
        end
        if ~exist(paths.xml,'dir')
            mkdir(paths.xml);
        end
        if ~exist(paths.res,'dir')
            mkdir(paths.res);
        end
        
        % Setup default config file.
        config.shiftSections = 1;
        config.autoReload = 1;
        config.showAxis = 1;
        config.fancyGraphics = 1;
        config.individualColours = 1;
        config.exportFile = 1;
        config.exportVar = 1;
        config.devWarn = 1;
        config.debugWarn = 1;
        config.showUI = 1;
        config.checkIp = 1;
        
        pref.lastXml = paths.xml;
        pref.lang = get(0,'language');
        pref.installLang = get(0,'language');
        pref.lengthUnits = localisation.units.lengthNames{1};
        pref.massUnits = localisation.units.massNames{1};
        pref.mainColour = [0.5 0.5 0.5];
        pref.secondColour = [0.5 0.5 0.5];
        pref.elevatorColour = [0.5 0.5 0.5];
        pref.finColour = [0.5 0.5 0.5];
        pref.defaultW = 0.85;
        pref.defaultH = 0.85;
        pref.licenceIp = '131.231.152.1';
        
        save(paths.con,'config','pref');
        
        % Write the images for use later.
        blackRGB = uint8(zeros(16,16,3));
        cogAlp = uint8([0 0 0 0 0 0 50 247 247 50 0 0 0 0 0 0; 0 0 8 43 ...
            0 0 157 255 255 157 0 0 43 8 0 0; 0 8 184 255 192 120 246 ...
            255 255 246 118 192 255 184 8 0; 0 43 255 255 255 255 255 ...
            255 255 255 255 255 255 255 43 0; 0 0 192 255 255 255 255 ...
            255 255 255 255 255 255 192 0 0; 0 0 119 255 255 248 110 15 ...
            15 110 248 255 255 120 0 0; 50 157 246 255 255 112 0 0 0 0 ...
            112 255 255 246 157 50; 247 255 255 255 255 19 0 0 0 0 20 ...
            255 255 255 255 247; 247 255 255 255 255 21 0 0 0 0 21 255 ...
            255 255 255 247; 50 157 246 255 255 118 0 0 0 0 118 255 255 ...
            246 157 50; 0 0 119 255 255 250 120 25 25 120 250 255 255 ...
            118 0 0; 0 0 192 255 255 255 255 255 255 255 255 255 255 ...
            192 0 0; 0 43 255 255 255 255 255 255 255 255 255 255 255 ...
            255 43 0; 0 8 184 255 192 119 246 255 255 246 119 192 255 ...
            184 8 0; 0 0 8 43 0 0 157 255 255 157 0 0 43 8 0 0; 0 0 0 0 ...
            0 0 50 247 247 50 0 0 0 0 0 0]);
        
        rightArrowAlp = uint8([0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0; 0 0 0 0 ...
            0 0 0 0 0 0 0 0 0 0 0 0; 100 130 130 130 35 0 39 130 130 ...
            130 97 0 0 0 0 0; 35 226 255 255 227 35 0 141 255 255 255 ...
            127 0 0 0 0; 0 35 226 255 255 227 35 0 141 255 255 255 128 ...
            0 0 0; 0 0 35 226 255 255 227 35 0 141 255 255 255 128 0 0; ...
            0 0 0 35 226 255 255 227 36 0 141 255 255 255 128 0; 0 0 0 ...
            0 35 232 255 255 227 32 0 141 255 255 255 128; 0 0 0 0 35 ...
            227 255 255 227 35 0 141 255 255 255 143; 0 0 0 35 227 255 ...
            255 228 37 1 141 255 255 255 145 0; 0 0 35 227 255 255 233 ...
            40 0 141 255 255 255 145 0 0; 0 35 227 255 255 232 44 0 137 ...
            255 255 255 142 0 0 0; 33 226 255 255 235 45 0 123 255 255 ...
            255 137 0 0 0 0; 103 148 148 148 45 0 31 130 147 148 107 0 ...
            0 0 0 0; 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0; 0 0 0 0 0 0 0 0 0 ...
            0 0 0 0 0 0 0]);
        
        leftArrowAlp = fliplr(rightArrowAlp);
        
        folderAlp = uint8([0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0;0,0,0,0,0,0,...
            0,0,0,0,0,0,0,0,0,0;0,9,86,93,93,93,83,1,0,0,0,0,0,0,0,0;0,...
            148,255,255,255,255,255,149,8,8,8,8,8,5,0,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,251,99,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,178,255,255,...
            255,255,255,255,255,255,255,255,255,255,178,0;0,149,255,255,...
            255,255,255,255,255,255,255,255,255,255,149,0;0,9,86,93,93,...
            93,93,93,93,93,93,93,93,86,9,0;0,0,0,0,0,0,0,0,0,0,0,0,0,0,...
            0,0;0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0]);
        
        
        imwrite(blackRGB,fullfile(paths.res,'cog.png'),'Alpha',cogAlp);
        imwrite(blackRGB,fullfile(paths.res,'rightarrow.png'),'Alpha',rightArrowAlp);
        imwrite(blackRGB,fullfile(paths.res,'leftarrow.png'),'Alpha',leftArrowAlp);
        imwrite(blackRGB,fullfile(paths.res,'folder.png'),'Alpha',folderAlp);
        
        % Write the export file.
        pythonStr = 'def main()\n\tprint(''Hello World''):\n\n\nmain()';
        
        fPy = fopen(fullfile(paths.res,'exportPlane.py'),'wt');
        fprintf(fPy,pythonStr);
        fclose(fPy);
        
        % Move the language file to maintain a tidy directory.
        if exist(fullfile(paths.root,'lang.mat'),'file')
            movefile(fullfile(paths.root,'lang.mat'),fullfile(paths.res,'lang.mat'));
            paths.lang = fullfile(paths.res,'lang.mat');
        elseif ~exist(fullfile(paths.res,'lang.mat'),'file')
            errorStruct.identifier = 'xflr2nx:CommandHandler:missingLangFile';
            errorStruct.message = 'No language file could be located.';
            error(errorStruct);
        end
        
        % Add the folders to the path so they can be used.
        addpath(genpath(paths.out));
        addpath(genpath(paths.dat));
        addpath(genpath(paths.xml));
        addpath(genpath(paths.res));
        
        % Initialise the DAT matrix by updating it.
        UpdateDatMatrix;
        
    end

    function [isPresentStr,isPresentColor,enableLvl2Str,enableButtonStr, enableIsPresentStr] = CheckForIp
        
        % Defaults.
        isPresentStr = 'IP checking disabled...';
        enableIsPresentStr = 'on';
        isPresentColor = [0 0 0];
        enableLvl2Str = 'off';
        enableButtonStr = 'off';
        
        % Check checkIp
        if config.checkIp
            enableButtonStr = 'on';
            if ispc
                % Call the OS to get the ipconfig (or equivalent). Error if fails.
                [status, result] = system('ipconfig /all');
                if status
                    error('xflr2nx:CheckForIP:systemCallFailed','Call to OS failed.');
                end
                
                % Look through existing IPs and see if required IP is present.
                oneByte =  '(1\d\d|2[0-4]\d|25[0-5]|\d\d|\d)';
                IPs = regexp(result, sprintf('((%s\\.){3}%s)',oneByte,oneByte),'match');
                if any(strcmp(IPs,pref.licenceIp))
                    isPresentStr = sprintf('Connected to required licence IP address: %s',pref.licenceIp);
                    isPresentColor = [1 0 0];
                    enableLvl2Str = 'on';
                else
                    isPresentStr = 'Not connected to licence IP! Export is diabled.';
                    isPresentColor = [0 0 0];
                    enableLvl2Str = 'off';
                end
            else
                ipPresentStr = '';
                enableLvl2Str = 'on';
            end                        
        else
            enableLvl2Str = 'on';
            enableIsPresentStr = 'off';
        end
        
        
    end

    function mat = rotx(a)
        % Mirrors functionality of toolbox. x-rotation matrix.
        mat = [1,0,0;0,cosd(a),-sind(a);0,sind(a),cosd(a)];
    end

    function ErrorHandler(varargin)
        % Global error handler.
        % Takes either a single MException or a function to run.
        
        newErr = 0;
        if isa(varargin{1},'MException')
            thisError = varargin{1};
            newErr = 1;
        else
            if length(varargin) == 1
                varargin{1}();
            else
                func = varargin{1};
                args = varargin{2:end};
                func(args{:});
            end
        end
        
        if newErr
            save(paths.config,'thisError','-append');            
            if debug
                rethrow(thisError);
            elseif strcmp(thisError.identifier(1:7),'xflr2nx')
                throwAsCaller(thisError);
            else
                error('xflr2nx:ErrorHandler:unknownError','An unknown error occurred.');
            end
        end
        
    end

%% == GRAPHICS FUNCTIONS ==================================================

    function DrawConflictGui(thisFoil,otherFoil)
        
        graphics.screenSize = get(0,'Screensize');
        figW = graphics.screenSize(3) * pref.defaultW;
        figH = graphics.screenSize(4) * pref.defaultH;
        
        graphics.f2 = figure(...
            'Visible','off',...
            'Position',[0,0,figW,figH],...
            'NumberTitle','off',...
            'Name',sprintf('%s %s %s',thisFoil.name,localisation.gui.conflictTitle,funcVersion),...
            'MenuBar','none',...
            'SizeChangedFcn',@UpdateSize);
        movegui(graphics.f2,'center');
        
        graphics.conflict.hConflictText = uicontrol(...
            'Style','text',...
            'HorizontalAlignment','left',...
            'String',sprintf('%s',localisation.gui.conflictText),...
            'Position', [10,figH-55,figW-20,45]);
        
        graphics.conflict.hLeftPanel = uipanel(...
            'Title',otherFoil.filename,...
            'FontSize',10,...
            'FontName','FixedWidth',...
            'Units','pixels',...
            'FontWeight','bold',...
            'Position',[10 45 ((figW/2)-15) (figH-110)]);
        
        graphics.conflict.hLeftName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.aerofoilName),...
            'Position',[((((figW/2)-15)/2)-100) (figH-160) 100 25]);
        
        graphics.conflict.hLeftFoilName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'Units','pixels',...
            'HorizontalAlignment','left',...
            'String',otherFoil.name,...
            'Position',[(((figW/2)-15)/2) (figH-160) 100 25]);
        
        graphics.conflict.hLeftPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.folder),...
            'Position',[((((figW/2)-15)/2)-100) (figH-185) 100 25]);
        
        graphics.conflict.hLeftFoilPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',extractAfter(otherFoil.folder,[paths.root,filesep]),...
            'Position',[(((figW/2)-15)/2) (figH-185) 100 25]);
        
        graphics.conflict.hLeftFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.fileFormat),...
            'Position',[((((figW/2)-15)/2)-100) (figH-210) 100 25]);
        
        graphics.conflict.hLeftFoilFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',otherFoil.format,...
            'Position',[(((figW/2)-15)/2) (figH-210) 100 25]);
        
        graphics.conflict.hLeftPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.numberPoints),...
            'Position',[((((figW/2)-15)/2)-100) (figH-235) 100 25]);
        
        graphics.conflict.hLeftFoilPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',num2str(otherFoil.numPoints(1)),...
            'Position',[(((figW/2)-15)/2) (figH-235) 100 25]);
        
        graphics.conflict.hLeftCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.sampleCoords),...
            'Position',[((((figW/2)-15)/2)-110) (figH-260) 110 25]);
        
        graphics.conflict.hLeftFoilCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',sprintf('%f, %f\n%f, %f\n%f, %f\n%f, %f\n%f, %f',otherFoil.coords(1,1),otherFoil.coords(1,2),otherFoil.coords(2,1),otherFoil.coords(2,2),otherFoil.coords(3,1),otherFoil.coords(3,2),otherFoil.coords(4,1),otherFoil.coords(4,2),otherFoil.coords(5,1),otherFoil.coords(5,2)),...
            'Position',[(((figW/2)-15)/2) (figH-310) 105 75]);
        
        graphics.conflict.hRightPanel = uipanel(...
            'Title',thisFoil.filename,...
            'FontSize',10,...
            'FontName','FixedWidth',...
            'Units','pixels',...
            'FontWeight','bold',...
            'Position',[((figW/2)+5) 45 ((figW/2)-15) (figH-110)]);
        
        graphics.conflict.hRightName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.aerofoilName),...
            'Position',[((((figW/2)-15)/2)-100) (figH-160) 100 25]);
        
        graphics.conflict.hRightFoilName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'Units','pixels',...
            'HorizontalAlignment','left',...
            'String',thisFoil.name,...
            'Position',[(((figW/2)-15)/2) (figH-160) 100 25]);
        
        graphics.conflict.hRightPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.folder),...
            'Position',[((((figW/2)-15)/2)-100) (figH-185) 100 25]);
        
        graphics.conflict.hRightFoilPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',extractAfter(thisFoil.folder,[paths.root,filesep]),...
            'Position',[(((figW/2)-15)/2) (figH-185) 100 25]);
        
        graphics.conflict.hRightFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.fileFormat),...
            'Position',[((((figW/2)-15)/2)-100) (figH-210) 100 25]);
        
        graphics.conflict.hRightFoilFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',thisFoil.format,...
            'Position',[(((figW/2)-15)/2) (figH-210) 100 25]);
        
        graphics.conflict.hRightPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.numberPoints),...
            'Position',[((((figW/2)-15)/2)-100) (figH-235) 100 25]);
        
        graphics.conflict.hRightFoilPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',num2str(thisFoil.numPoints(1)),...
            'Position',[(((figW/2)-15)/2) (figH-235) 100 25]);
        
        graphics.conflict.hRightCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.sampleCoords),...
            'Position',[((((figW/2)-15)/2)-110) (figH-260) 110 25]);
        
        graphics.conflict.hRightFoilCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',sprintf('%f, %f\n%f, %f\n%f, %f\n%f, %f\n%f, %f',thisFoil.coords(1,1),thisFoil.coords(1,2),thisFoil.coords(2,1),thisFoil.coords(2,2),thisFoil.coords(3,1),thisFoil.coords(3,2),thisFoil.coords(4,1),thisFoil.coords(4,2),thisFoil.coords(5,1),thisFoil.coords(5,2)),...
            'Position',[(((figW/2)-15)/2) (figH-310) 105 75]);
        
        graphics.conflict.hOpenDatButton = uicontrol(...
            'Style','pushbutton',...
            'Parent',graphics.f2,...
            'Callback',@OpenDat,...
            'String',sprintf('%s',localisation.gui.openDatFolder),...
            'Position',[(figW-330) 10 100 25]);
        
        graphics.conflict.hReloadButton = uicontrol(...
            'Style','pushbutton',...
            'Parent',graphics.f2,...
            'Callback',@Reload,...
            'String',sprintf('%s',localisation.gui.reload),...
            'Position',[(figW-220) 10 100 25]);
        
        graphics.conflict.hCloseButton = uicontrol(...
            'Style','pushbutton',...
            'Parent',graphics.f2,...
            'String',sprintf('%s',localisation.gui.close),...
            'Callback',@Close,...
            'Position',[(figW-110) 10 100 25]);
        
        graphics.conflict.f2.Visible = 'on';
        
        function Close(~,~,~)
            close(graphics.f2);
        end
        function OpenDat(~,~,~)
            winopen(paths.dat);
            uiresume
        end
        function Reload(~,~,~)
            close
            UpdateDatMatrix;
        end
        function UpdateSize(~,~,~)
            currentSize = graphics.f2.Position(3:4);
            figureHeight = currentSize(2);
            figureWidth = currentSize(1);
            % Update sizes.
            graphics.conflict.hConflictText.Position = [10 (figureHeight-55) (figureWidth-20) 45];
            graphics.conflict.hLeftPanel.Position = [10 45 ((figureWidth/2)-15) (figureHeight-110)];
            graphics.conflict.hLeftName.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-160) 150 25];
            graphics.conflict.hLeftFoilName.Position = [(((figureWidth/2)-15)/2) (figureHeight-160) 150 25];
            graphics.conflict.hLeftPath.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-185) 150 25];
            graphics.conflict.hLeftFoilPath.Position = [(((figureWidth/2)-15)/2) (figureHeight-185) 150 25];
            graphics.conflict.hLeftFormat.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-210) 150 25];
            graphics.conflict.hLeftFoilFormat.Position = [(((figureWidth/2)-15)/2) (figureHeight-210) 150 25];
            graphics.conflict.hLeftPointNum.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-235) 150 25];
            graphics.conflict.hLeftFoilPointNum.Position = [(((figureWidth/2)-15)/2) (figureHeight-235) 150 25];
            graphics.conflict.hLeftCoords.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-260) 150 25];
            graphics.conflict.hLeftFoilCoords.Position = [(((figureWidth/2)-15)/2) (figureHeight-310) 150 75];
            graphics.conflict.hRightPanel.Position = [((figureWidth/2)+5) 45 ((figureWidth/2)-15) (figureHeight-110)];
            graphics.conflict.hRightName.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-160) 150 25];
            graphics.conflict.hRightFoilName.Position = [(((figureWidth/2)-15)/2) (figureHeight-160) 150 25];
            graphics.conflict.hRightPath.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-185) 150 25];
            graphics.conflict.hRightFoilPath.Position = [(((figureWidth/2)-15)/2) (figureHeight-185) 150 25];
            graphics.conflict.hRightFormat.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-210) 150 25];
            graphics.conflict.hRightFoilFormat.Position = [(((figureWidth/2)-15)/2) (figureHeight-210) 150 25];
            graphics.conflict.hRightPointNum.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-235) 150 25];
            graphics.conflict.hRightFoilPointNum.Position = [(((figureWidth/2)-15)/2) (figureHeight-235) 150 25];
            graphics.conflict.hRightCoords.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-260) 150 25];
            graphics.conflict.hRightFoilCoords.Position = [(((figureWidth/2)-15)/2) (figureHeight-310) 150 75];
            graphics.conflict.hOpenDatButton.Position = [(figureWidth-330) 10 100 25];
            graphics.conflict.hReloadButton.Position = [(figureWidth-220) 10 100 25];
            graphics.conflict.hCloseButton.Position = [(figureWidth-110) 10 100 25];
        end
    end

    function DrawXmlGui
        % GETXMLGUI Produces a GUI to get the XML file.
        
        % Error case.
        choice = 0;
        
        %  Create and hide the UI as it is being constructed.
        graphics.f = uifigure('Visible','off');
        graphics.f.Position = [0 0 figW figH];
        graphics.f.NumberTitle = 'off';
        graphics.f.Name = 'XFLR to NX 2.0.0';
        
        movegui(graphics.f,'center');
        
        % Setup grids.
        graphics.level1 = uigridlayout(graphics.f);
        graphics.level1.ColumnWidth = {35,'1x',100,35,100};
        graphics.level1.RowHeight = {25,'1x',25};
        
        % Load config.
        load(paths.con,'config','pref');
        
        % Get the key data.
        [sections,planeName,planeDes,massStr,spanStr,fileSize,lines,fileName] = PreScanXml(pref.lastXml);
        
        % Top line.
        graphics.choice.pathEdit = uieditfield(graphics.level1);
        graphics.choice.pathEdit.Value = pref.lastXml;
        graphics.choice.pathEdit.ValueChangedFcn = @PathUpdated;
        graphics.choice.pathEdit.Layout.Row = 1;
        graphics.choice.pathEdit.Layout.Column = [1 3];
        graphics.choice.pathEdit.Tooltip = 'The .xml file which defines the plane.';
        
        graphics.choice.chooseButton = uibutton(graphics.level1);
        graphics.choice.chooseButton.Text = '';
        graphics.choice.chooseButton.Layout.Row = 1;
        graphics.choice.chooseButton.Layout.Column = 4;
        graphics.choice.chooseButton.Icon = fullfile(paths.res,'folder.png');
        graphics.choice.chooseButton.ButtonPushedFcn = @ChoosePath;
                
        graphics.choice.selectButton = uibutton(graphics.level1);
        graphics.choice.selectButton.Text = 'Import...';
        graphics.choice.selectButton.Layout.Row = 1;
        graphics.choice.selectButton.Layout.Column = 5;
        graphics.choice.selectButton.Tooltip = 'Choose which .xml file to process.';
        graphics.choice.selectButton.ButtonPushedFcn = @ImportPlane;
        
        % Bottom line.
        graphics.choice.closeButton = uibutton(graphics.level1);
        graphics.choice.closeButton.Text = 'Close';
        graphics.choice.closeButton.ButtonPushedFcn = @Cancel;
        graphics.choice.closeButton.Layout.Row = 3;
        graphics.choice.closeButton.Layout.Column = 5;
        
        graphics.choice.settingsButton = uibutton(graphics.level1);
        graphics.choice.settingsButton.Icon = fullfile(paths.res,'cog.png');
        graphics.choice.settingsButton.Text = '';
        graphics.choice.settingsButton.ButtonPushedFcn = @ShowSettings;
        graphics.choice.settingsButton.Layout.Row = 3;
        graphics.choice.settingsButton.Layout.Column = 1;
        
        % Settings.
        graphics.settings.level1 = uigridlayout(graphics.f);
        graphics.settings.level1.ColumnWidth = {35,'1x',100,100};
        graphics.settings.level1.RowHeight = {'1x',25};
        graphics.settings.level1.Visible = 'off';
        
        graphics.settings.cancelButton = uibutton(graphics.settings.level1);
        graphics.settings.cancelButton.Text = sprintf('%s',localisation.gui.cancel);
        graphics.settings.cancelButton.ButtonPushedFcn = @CancelSettings;
        graphics.settings.cancelButton.Layout.Row = 2;
        graphics.settings.cancelButton.Layout.Column = 4;
        
        graphics.settings.saveButton = uibutton(graphics.settings.level1);
        graphics.settings.saveButton.Text = sprintf('Save');
        graphics.settings.saveButton.ButtonPushedFcn = @SaveSettings;
        graphics.settings.saveButton.Layout.Row = 2;
        graphics.settings.saveButton.Layout.Column = 3;
        
        graphics.settings.level2 = uigridlayout(graphics.settings.level1);
        graphics.settings.level2.ColumnWidth = {'1x','3x'};
        graphics.settings.level2.RowHeight = {'1x'};
        graphics.settings.level2.Layout.Row = 1;
        graphics.settings.level2.Layout.Column = [1 4];
        
        graphics.settings.tree = uitree(graphics.settings.level2);
        graphics.settings.tree.Layout.Row = 1;
        graphics.settings.tree.Layout.Row = 1;
        graphics.settings.tree.SelectionChangedFcn = @SettingsNodeChanged;
        
        graphics.settings.configNode = uitreenode(graphics.settings.tree,'Text','Configuration');
        graphics.settings.prefNode = uitreenode(graphics.settings.tree,'Text','Preferences');
        
        AddTreeNodes(graphics.settings.configNode,config);
        AddTreeNodes(graphics.settings.prefNode,pref);
        collapse(graphics.settings.tree);
        
        graphics.settings.level3 = uigridlayout(graphics.settings.level2);
        graphics.settings.level3.ColumnWidth = {'1x','2x'};
        graphics.settings.level3.RowHeight = {25,25,'1x'};
        graphics.settings.level3.Layout.Row = 1;
        graphics.settings.level3.Layout.Column = 2;
        
        graphics.settings.typeLab = uilabel(graphics.settings.level3);
        graphics.settings.typeLab.Text = 'Data Type:';
        graphics.settings.typeLab.Layout.Row = 1;
        graphics.settings.typeLab.Layout.Column = 1;
        
        graphics.settings.type = uieditfield(graphics.settings.level3);
        graphics.settings.type.Value = '';
        graphics.settings.type.Layout.Row = 1;
        graphics.settings.type.Layout.Column = 2;
        graphics.settings.type.Enable = 'off';
        
        graphics.settings.valueLab = uilabel(graphics.settings.level3);
        graphics.settings.valueLab.Text = 'Value:';
        graphics.settings.valueLab.Layout.Row = 2;
        graphics.settings.valueLab.Layout.Column = 1;
        
        graphics.settings.value = uieditfield(graphics.settings.level3);
        graphics.settings.value.Value = '';
        graphics.settings.value.Layout.Row = 2;
        graphics.settings.value.Layout.Column = 2;
        
        % Lvl 2 grid.
        graphics.level2 = uigridlayout(graphics.level1);
        graphics.level2.ColumnWidth = {'1x','1x','1x'};
        graphics.level2.RowHeight = {'1x','1x','1x'};
        graphics.level2.Layout.Row = 2;
        graphics.level2.Layout.Column = [1 5];
        
        % Add the axis.
        graphics.axesgrid = uigridlayout(graphics.level2);
        graphics.axesgrid.Layout.Row = [1 2];
        graphics.axesgrid.Layout.Column = [2 3];
        graphics.axesgrid.RowHeight = {'1x'};
        graphics.axesgrid.ColumnWidth = {'1x',35,0,0};
        
        graphics.choice.collapseButton = uibutton(graphics.axesgrid);
        graphics.choice.collapseButton.Text = '';
        graphics.choice.collapseButton.Icon = fullfile(paths.res,'leftarrow.png');
        graphics.choice.collapseButton.Layout.Row = 1;
        graphics.choice.collapseButton.Layout.Column = 2;
        
        graphics.choice.wingPlotAxes = uiaxes(graphics.level2);
        graphics.choice.wingPlotAxes.Layout.Row = [1 2];
        graphics.choice.wingPlotAxes.Layout.Column = [2 3];
        
        % Add the panels.
        graphics.choice.importOptionsPanel = uipanel(graphics.level2);
        graphics.choice.importOptionsPanel.Title = sprintf('%s',localisation.gui.outputOptions);
        graphics.choice.importOptionsPanel.FontWeight = 'bold';
        graphics.choice.importOptionsPanel.Layout.Row = 3;
        graphics.choice.importOptionsPanel.Layout.Column = 1;
        
        graphics.choice.previewPanel = uipanel(graphics.level2);
        graphics.choice.previewPanel.Title = sprintf('%s',localisation.gui.importPreview);
        graphics.choice.previewPanel.FontWeight = 'bold';
        graphics.choice.previewPanel.Layout.Row = [1 2];
        graphics.choice.previewPanel.Layout.Column = 1;
        graphics.choice.previewPanel.Scrollable = 'on';
        
        graphics.choice.exportPanel = uipanel(graphics.level2);
        graphics.choice.exportPanel.Title = 'Export';
        graphics.choice.exportPanel.FontWeight = 'bold';
        graphics.choice.exportPanel.Layout.Row = 3;
        graphics.choice.exportPanel.Layout.Column = 3;
        
        % Preview panel.
        graphics.level3.preview = uigridlayout(graphics.choice.previewPanel);
        graphics.level3.preview.ColumnWidth = {'1x','1x'};
        graphics.level3.preview.RowHeight = {12,12,12,12,12,12,12};
        
        graphics.choice.fileNameText = uilabel(graphics.level3.preview);
        graphics.choice.fileNameText.Text = sprintf('%s:',localisation.gui.filename);
        graphics.choice.fileNameText.HorizontalAlignment = 'right';
        graphics.choice.fileNameText.Layout.Row = 1;
        graphics.choice.fileNameText.Layout.Column = 1;
        
        graphics.choice.fileName = uilabel(graphics.level3.preview);
        graphics.choice.fileName.Text = fileName;
        graphics.choice.fileName.HorizontalAlignment = 'left';
        graphics.choice.fileName.Layout.Row = 1;
        graphics.choice.fileName.Layout.Column = 2;
        
        graphics.choice.fileSizeText = uilabel(graphics.level3.preview);
        graphics.choice.fileSizeText.Text = sprintf('%s:',localisation.gui.size);
        graphics.choice.fileSizeText.HorizontalAlignment = 'right';
        graphics.choice.fileSizeText.Layout.Row = 2;
        graphics.choice.fileSizeText.Layout.Column = 1;
        
        graphics.choice.fileSize = uilabel(graphics.level3.preview);
        graphics.choice.fileSize.Text = fileSize;
        graphics.choice.fileSize.HorizontalAlignment = 'left';
        graphics.choice.fileSize.Layout.Row = 2;
        graphics.choice.fileSize.Layout.Column = 2;
        
        graphics.choice.sectionsText = uilabel(graphics.level3.preview);
        graphics.choice.sectionsText.Text = {'Sections:'};
        graphics.choice.sectionsText.HorizontalAlignment = 'right';
        graphics.choice.sectionsText.Layout.Row = 3;
        graphics.choice.sectionsText.Layout.Column = 1;
        
        graphics.choice.sections = uilabel(graphics.level3.preview);
        graphics.choice.sections.Text = sections;
        graphics.choice.sections.HorizontalAlignment = 'left';
        graphics.choice.sections.Layout.Row = 3;
        graphics.choice.sections.Layout.Column = 2;
        
        graphics.choice.planeNameText = uilabel(graphics.level3.preview);
        graphics.choice.planeNameText.Text = 'Plane Name:';
        graphics.choice.planeNameText.HorizontalAlignment = 'right';
        graphics.choice.planeNameText.Layout.Row = 4;
        graphics.choice.planeNameText.Layout.Column = 1;
        
        graphics.choice.planeName = uilabel(graphics.level3.preview);
        graphics.choice.planeName.Text = planeName;
        graphics.choice.planeName.HorizontalAlignment = 'left';
        graphics.choice.planeName.Layout.Row = 4;
        graphics.choice.planeName.Layout.Column = 2;
        
        graphics.choice.descriptionText = uilabel(graphics.level3.preview);
        graphics.choice.descriptionText.Text = 'Description:';
        graphics.choice.descriptionText.HorizontalAlignment = 'right';
        graphics.choice.descriptionText.Layout.Row = 5;
        graphics.choice.descriptionText.Layout.Column = 1;
        
        graphics.choice.description = uilabel(graphics.level3.preview);
        graphics.choice.description.Text = planeDes;
        graphics.choice.description.HorizontalAlignment = 'left';
        graphics.choice.description.Layout.Row = 5;
        graphics.choice.description.Layout.Column = 2;
        
        graphics.choice.massText = uilabel(graphics.level3.preview);
        graphics.choice.massText.Text = 'Mass:';
        graphics.choice.massText.HorizontalAlignment = 'right';
        graphics.choice.massText.Layout.Row = 6;
        graphics.choice.massText.Layout.Column = 1;
        
        graphics.choice.mass = uilabel(graphics.level3.preview);
        graphics.choice.mass.Text = massStr;
        graphics.choice.mass.HorizontalAlignment = 'left';
        graphics.choice.mass.Layout.Row = 6;
        graphics.choice.mass.Layout.Column = 2;
        
        graphics.choice.spanText = uilabel(graphics.level3.preview);
        graphics.choice.spanText.Text = 'Span:';
        graphics.choice.spanText.HorizontalAlignment = 'right';
        graphics.choice.spanText.Layout.Row = 7;
        graphics.choice.spanText.Layout.Column = 1;
        
        graphics.choice.span = uilabel(graphics.level3.preview);
        graphics.choice.span.Text = spanStr;
        graphics.choice.span.HorizontalAlignment = 'left';
        graphics.choice.span.Layout.Row = 7;
        graphics.choice.span.Layout.Column = 2;
        
        % Options panel.
        graphics.level3.options = uigridlayout(graphics.choice.importOptionsPanel);
        graphics.level3.options.ColumnWidth = {'1x','1x'};
        graphics.level3.options.RowHeight = {rowH,rowH,rowH,rowH};
        
        graphics.choice.lengthText = uilabel(graphics.level3.options);
        graphics.choice.lengthText.Text = sprintf('%s:',localisation.gui.lengthUnits);
        graphics.choice.lengthText.HorizontalAlignment = 'right';
        graphics.choice.lengthText.Layout.Row = 1;
        graphics.choice.lengthText.Layout.Column = 1;
        
        graphics.choice.lengthMenu = uidropdown(graphics.level3.options);
        graphics.choice.lengthMenu.Items = localisation.units.lengthNames;
        graphics.choice.lengthMenu.Value = pref.lengthUnits;
        graphics.choice.lengthMenu.Layout.Row = 1;
        graphics.choice.lengthMenu.Layout.Column = 2;
        
        graphics.choice.massText2 = uilabel(graphics.level3.options);
        graphics.choice.massText2.Text = sprintf('%s:',localisation.gui.massUnits);
        graphics.choice.massText2.HorizontalAlignment = 'right';
        graphics.choice.massText2.Layout.Row = 2;
        graphics.choice.massText2.Layout.Column = 1;
        
        graphics.choice.massMenu = uidropdown(graphics.level3.options);
        graphics.choice.massMenu.Items = localisation.units.massNames;
        graphics.choice.massMenu.Value = pref.massUnits;
        graphics.choice.massMenu.Layout.Row = 2;
        graphics.choice.massMenu.Layout.Column = 2;
        
        graphics.choice.shiftSectionsText = uilabel(graphics.level3.options);
        graphics.choice.shiftSectionsText.Text = sprintf('%s:',localisation.gui.shiftSections);
        graphics.choice.shiftSectionsText.HorizontalAlignment = 'right';
        graphics.choice.shiftSectionsText.Layout.Row = 3;
        graphics.choice.shiftSectionsText.Layout.Column = 1;
        
        graphics.choice.shiftSectionsCheckbox = uicheckbox(graphics.level3.options);
        graphics.choice.shiftSectionsCheckbox.Value = config.shiftSections;
        graphics.choice.shiftSectionsCheckbox.Text = '';
        graphics.choice.shiftSectionsCheckbox.Layout.Row = 3;
        graphics.choice.shiftSectionsCheckbox.Layout.Column = 2;
        
        graphics.choice.autoReloadText = uilabel(graphics.level3.options);
        graphics.choice.autoReloadText.Text = sprintf('%s:',localisation.gui.autoReload);
        graphics.choice.autoReloadText.HorizontalAlignment = 'right';
        graphics.choice.autoReloadText.Layout.Row = 4;
        graphics.choice.autoReloadText.Layout.Column = 1;
        
        graphics.choice.autoReloadCheckbox = uicheckbox(graphics.level3.options);
        graphics.choice.autoReloadCheckbox.Value = config.autoReload;
        graphics.choice.autoReloadCheckbox.Text = '';
        graphics.choice.autoReloadCheckbox.Layout.Row = 4;
        graphics.choice.autoReloadCheckbox.Layout.Column = 2;
        
        % Export panel.
        graphics.level3.export = uigridlayout(graphics.choice.exportPanel);
        graphics.level3.export.RowHeight = {'1x',25};
        graphics.level3.export.ColumnWidth = {'1x'};
        
        graphics.choice.exportButton = uibutton(graphics.level3.export);
        graphics.choice.exportButton.Layout.Row = 2;
        graphics.choice.exportButton.Layout.Column = 1;
        graphics.choice.exportButton.Text = 'Export';
        graphics.choice.exportButton.ButtonPushedFcn = @OK;
        
        % Process the path update from the initial draw.
        PathUpdated;
        
        % Apply visual settings and plot the three wings.
        hold(graphics.choice.wingPlotAxes,'on');
        axis(graphics.choice.wingPlotAxes,'equal');
        grid(graphics.choice.wingPlotAxes,'on');
        if ~config.showAxis
            axis(graphics.choice.wingPlotAxes,'off');
        end
        view(graphics.choice.wingPlotAxes,3);
        axis(graphics.choice.wingPlotAxes,'tight');
      
        graphics.f.Visible = 'on';
              
        function ImportPlane(~,~,~)
            raw = xml2struct(graphics.choice.pathEdit.Value);
            UnpackPlane(raw);
            partNames = {'mainWing','secondWing','elevator','fin'};
            thisParts = partNames(ismember(partNames,fieldnames(plane)));
            for part = 1:length(thisParts)
                Process2(thisParts{part});
            end
            cla(graphics.choice.wingPlotAxes);
            WingPlot(graphics.mainWingCoords,pref.mainColour);
            if config.individualColours
                if ismember('secondWing',thisParts)
                    WingPlot(graphics.secondWingCoords,pref.secondColour);
                end
                if ismember('elevator',thisParts)
                    WingPlot(graphics.elevatorCoords,pref.elevatorColour);
                end
                if ismember('fin',thisParts)
                    WingPlot(graphics.finCoords,pref.finColour);
                end
            else
                if ismember('secondWing',thisParts)
                    WingPlot(graphics.secondWingCoords,pref.mainColour);
                end
                if ismember('elevator',thisParts)
                    WingPlot(graphics.elevatorCoords,pref.mainColour);
                end
                if ismember('fin',thisParts)
                    WingPlot(graphics.finCoords,pref.mainColour);
                end
            end
            
        end
        function ChoosePath(~,~,~)
            [filename,pathname] = uigetfile('*.xml',sprintf('%s',localisation.gui.chooseXml),paths.xml);
            if ~isequal(filename,0)
                % Set the path to the file.
                graphics.choice.pathEdit.Value = fullfile(pathname,filename);
                PathUpdated;
            end
        end
        function PathUpdated(~,~,~)
            
            % Assumes the value in pathEdit is a char.
            [path,filename,ext] = fileparts(graphics.choice.pathEdit.Value);
            
            % Red if it's not an XML.
            if ~strcmp(ext,'.xml')
                graphics.choice.pathEdit.BackgroundColor = [1 0.9 0.9];
                graphics.choice.pathEdit.FontColor = [1 0 0];
                return
            end
            
            % Set it's name.
            graphics.choice.fileName.Text = [filename,ext];
            
            % Get the basic data.
            [sections,planeName,planeDes,massStr,spanStr,fileSize,lines] = PreScanXml([path,filesep,filename,ext]);
            
            % Assign the strings.
            graphics.choice.fileSize.Text = fileSize;
            graphics.choice.sections.Text = sections;
            graphics.choice.planeName.Text = planeName;
            graphics.choice.planeDescription.Text = planeDes;
            graphics.choice.mass.Text = massStr;
            graphics.choice.span.Text = spanStr;
            
            % Adjust the height of that row.
            graphics.level3.preview.RowHeight{3} = rowH + 15*(lines-1);
            secText = cell(lines+1,1); % One longer to force at top.
            secText{1} = 'Sections:';
            secText(2:end) = {''};
            graphics.choice.sectionsText.Text = secText;
            
        end
        function Cancel(~,~,~)
            close(graphics.f)
        end
        function OK(~,~,~)
            
            % Disable controls.
            children = fieldnames(graphics.choice);
            for i = 1:length(children)
                try
                    graphics.choice.(children{i}).Enable = 'off';
                end
            end
            drawnow;
            
            % Add the path to the paths variable.
            choice = graphics.choice.pathEdit.Value;
            pref.lastXml = choice;
            
            % Store/execute the options.
            config.shiftSections = graphics.choice.shiftSectionsCheckbox.Value;
            config.autoReload = graphics.choice.autoReloadCheckbox.Value;
            pref.massUnits = graphics.choice.massMenu.Value;
            pref.lengthUnits = graphics.choice.lengthMenu.Value;
            
            % Save the data.
            save(paths.con,'config','pref','-append');
            
            % Proceed.
            xmlPath = choice; % Bodge for now
            [~,xmlName,~] = fileparts(xmlPath);
            
            % Autoreload.
            if config.autoReload
                UpdateDatMatrix;
            end
            
            % Make a new folder for the output files.
            if config.exportFile
                parentDir = fullfile(paths.out,xmlName,filesep);
                if ~exist(parentDir,'dir')
                    DebugLog('Parent directory not found. Attempting to make one...');
                    mkdir(parentDir);
                    DebugLog('Parent directory made successfully...');
                else
                    DebugLog('Parent directory found...');
                end
                dateAndTime = datestr(datetime('now'),localisation.dateTimeFormat);
                pref.lastOutputDir = fullfile(parentDir,dateAndTime);
                mkdir(pref.lastOutputDir)
                DebugLog('Output directory made successfully...')
                save(paths.con,'pref','config');
            end
            
            % Main function
            partNames = {'mainWing','secondWing','elevator','fin'};
            thisParts = partNames(ismember(partNames,fieldnames(plane)));
            for part = 1:length(thisParts)
                Process(thisParts{part});
            end
            
            % Tidy up name for output, then assign variable in the base workspace.
            if config.exportVar
                if strcmp(plane.name,'Plane Name')
                    varName = xmlName;
                else
                    varName = plane.name;
                end
                assignin('base',sprintf(NameTidy2(varName)),plane);
                DebugLog('Wrote the output variable to base workspace successfully...');
            end
            
            % Re-enable controls.
             children = fieldnames(graphics.choice);
            for i = 1:length(children)
                try
                    graphics.choice.(children{i}).Enable = 'on';
                end
            end
            drawnow;
            
        end
        function CancelSettings(~,~)
            
            graphics.settings.level1.Visible = 'off';
            graphics.level1.Visible = 'on';
            graphics.f.Name = sprintf('%s %s',localisation.gui.chooseXmlTitle,funcVersion);
            
        end
        function ShowSettings(~,~)
            
            graphics.level1.Visible = 'off';
            graphics.settings.level1.Visible = 'on';
            graphics.f.Name = sprintf('%s %s','Settings - XFLR to NX',funcVersion);
            
            % Dummy config in case of changes.
            configChanged = config;
            prefChanged = pref;
            
        end
        function SaveSettings(~,~)
            
            config = configChanged;
            pref = prefChanged;
            
            graphics.settings.level1.Visible = 'off';
            graphics.level1.Visible = 'on';
            graphics.f.Name = sprintf('%s %s',localisation.gui.chooseXmlTitle,funcVersion);
            
        end
        function SettingsNodeChanged(~,event)
            
            % Save old value.
            if ~isempty(event.PreviousSelectedNodes)
                if strcmp(event.PreviousSelectedNodes.Parent.Text,'Configuration')
                    configChanged.(event.PreviousSelectedNodes.Text) = graphics.settings.value.Value;
                elseif strcmp(event.PreviousSelectedNodes.Parent.Text,'Preferences')
                    prefChanged.(event.PreviousSelectedNodes.Text) = graphics.settings.value.Value;
                end
            end
            
            
            graphics.settings.value.Value = MakeChar(event.SelectedNodes.NodeData);
            graphics.settings.type.Value = class(event.SelectedNodes.NodeData);
            
        end
    end

    function CompleteGuiLeg
        % COMPLETEGUI draws the GUI window which shows upon completion of
        % the file writing.
        
        % Configure figure for completed GUI.
        clf(graphics.f)
        graphics.f.Name = sprintf('%s %s %s',plane.name,localisation.gui.resultsTitle,funcVersion);
        set(graphics.f, 'SizeChangedFcn', @ResizeCompleteGUI);
        
        % Load variables.
        load(sprintf('%s\\resources\\config.mat',rootFolder),'config','pref');
        
        try
            pref.mainColour = plane.mainWing.colour(1:3)/255;
        end
        try
            pref.secondColour = plane.secondWing.colour(1:3)/255;
        end
        try
            pref.elevatorColour = plane.elevator.colour(1:3)/255;
        end
        try
            pref.finColour = plane.fin.colour(1:3)/255;
        end
        
        graphics.complete.tabGroup = uitabgroup(graphics.f);
        
        % Disable adjustment if fancy graphics is off.
        if config.individualColours
            enableStr = 'on';
        else
            enableStr = 'off';
        end
        
        % Check how many files were exported.
        try
            files = dir(pref.lastOutputDir);
            exportNum = length(files) - 2;
        catch
            exportNum = 0;
        end
        if exportNum == 1
            fileStr = 'file';
        else
            fileStr = 'files';
        end
        
        currentSize = graphics.f.Position(3:4);
        figureHeight = currentSize(2);
        figureWidth = currentSize(1);
        panelLeft = 1;
        panelHalf = ((((figureWidth/2)-15)/2)-1);
        panelRight = (((figureWidth/2)-15)/2);
        
        % Add new tab.
        graphics.complete.tabOverview = uitab(...
            graphics.complete.tabGroup,...
            'Title',sprintf('%s',localisation.gui.overview));
        
        % File overview panel.
        graphics.complete.overview.lPanel = uipanel(...
            'Parent',graphics.complete.tabOverview,...
            'Title','Output Summary',...
            'Units','pixels',...
            'FontWeight','bold');
        
        graphics.complete.overview.fileExportText = uicontrol(...
            'Parent',graphics.complete.overview.lPanel,...
            'Style','text',...
            'String','Files Exported:',...
            'HorizontalAlignment','right');
        
        graphics.complete.overview.fileExport = uicontrol(...
            'Parent',graphics.complete.overview.lPanel,...
            'Style','text',...
            'String',sprintf('%d %s',exportNum,fileStr),...
            'HorizontalAlignment','left');
        
        % Preview options.
        graphics.complete.overview.rPanel = uipanel(...
            'Parent',graphics.complete.tabOverview,...
            'Title','Preview Options',...
            'Units','pixels',...
            'FontWeight','bold');
        
        graphics.complete.overview.individualColoursCheckbox = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','check',...
            'Units','pixels',...
            'Value',config.individualColours,...
            'String','Colour each wing section separately',...
            'Callback',@ToggleIndividualColours,...
            'Enable',enableStr);
        
        
        graphics.complete.overview.mainColourText = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','text',...
            'Units','pixels',...
            'String','Main Wing Colour:',...
            'HorizontalAlignment','right',...
            'Enable',enableStr);
        
        graphics.complete.overview.mainColour = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','pushbutton',...
            'Units','pixels',...
            'BackgroundColor',pref.mainColour,...
            'Callback',@GetColour,...
            'UserData','Main Wing',...
            'Enable',enableStr);
        
        graphics.complete.overview.secondColourText = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','text',...
            'Units','pixels',...
            'String','Second Wing Colour:',...
            'HorizontalAlignment','right',...
            'Enable',enableStr);
        
        graphics.complete.overview.secondColour = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','pushbutton',...
            'Units','pixels',...
            'BackgroundColor',pref.secondColour,...
            'UserData','Second Wing',...
            'Callback',@GetColour,...
            'Enable',enableStr,...
            'Position',[panelRight,(figureHeight-200),33,25]);
        
        graphics.complete.overview.elevatorColourText = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','text',...
            'Units','pixels',...
            'String','Elevator Colour:',...
            'HorizontalAlignment','right',...
            'Enable',enableStr);
        
        graphics.complete.overview.elevatorColour = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','pushbutton',...
            'Units','pixels',...
            'BackgroundColor',pref.elevatorColour,...
            'UserData','Elevator',...
            'Callback',@GetColour,...
            'Enable',enableStr);
        
        graphics.complete.overview.finColourText = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','text',...
            'Units','pixels',...
            'String','Fin Colour:',...
            'HorizontalAlignment','right',...
            'Enable',enableStr);
        
        graphics.complete.overview.finColour = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','pushbutton',...
            'Units','pixels',...
            'BackgroundColor',pref.finColour,...
            'UserData','Fin',...
            'Callback',@GetColour,...
            'Enable',enableStr);
        
        graphics.complete.overview.UpdateButton = uicontrol(...
            'Parent',graphics.complete.overview.rPanel,...
            'Style','pushbutton',...
            'Units','pixels',...
            'String','Update',...
            'Callback',@UpdatePreview,...
            'Enable',enableStr);
        
        graphics.complete.overview.CloseButton = uicontrol(...
            'Parent',graphics.complete.tabOverview,...
            'Style','pushbutton',...
            'Units','pixels',...
            'String','Close',...
            'Callback',@Close);
        
        graphics.complete.tabPreview = uitab(...
            graphics.complete.tabGroup,...
            'Title',sprintf('%s',localisation.gui.preview));
        
        graphics.complete.preview.hWingPlotAxes = axes(...
            'Units','pixels',...
            'Parent',graphics.complete.tabPreview,...
            'Position',[10, 10, (figureWidth-20), (figureHeight-45)]);
        
        ResizeCompleteGUI;
        
        % Apply visual settings and plot the three wings.
        hold on
        axis equal
        grid on
        if ~graphics.showAxis
            axis off       %why would you turn this off.. Its so confusing without axis
        end
        WingPlot(graphics.mainWingCoords,pref.mainColour);
        if config.individualColours
            WingPlot(graphics.secondWingCoords,pref.secondColour);
            WingPlot(graphics.elevatorCoords,pref.elevatorColour);
            WingPlot(graphics.finCoords,pref.finColour);
        else
            WingPlot(graphics.secondWingCoords,pref.mainColour);
            WingPlot(graphics.elevatorCoords,pref.mainColour);
            WingPlot(graphics.finCoords,pref.mainColour);
        end
        view(3);
        axis tight
        rotate3d(graphics.complete.preview.hWingPlotAxes,'on')
        
        function Close(~,~)
            close(graphics.f)
            return
        end
        function UpdatePreview(~,~)
            % Save preferences
            pref.mainColour = graphics.complete.overview.mainColour.BackgroundColor;
            pref.secondColour = graphics.complete.overview.secondColour.BackgroundColor;
            pref.elevatorColour = graphics.complete.overview.elevatorColour.BackgroundColor;
            pref.finColour = graphics.complete.overview.finColour.BackgroundColor;
            pref.individualColours = graphics.complete.overview.individualColoursCheckbox.Value;
            save(sprintf('%s\\resources\\config.mat',rootFolder),'config','pref','-append')
            
            % Clear axes and replot.
            cla(graphics.complete.preview.hWingPlotAxes)
            hold on
            axis equal
            grid on
            if ~graphics.showAxis
                axis off
            end
            WingPlot(graphics.mainWingCoords,pref.mainColour);
            if config.individualColours
                WingPlot(graphics.secondWingCoords,pref.secondColour);
                WingPlot(graphics.elevatorCoords,pref.elevatorColour);
                WingPlot(graphics.finCoords,pref.finColour);
            else
                WingPlot(graphics.secondWingCoords,pref.mainColour);
                WingPlot(graphics.elevatorCoords,pref.mainColour);
                WingPlot(graphics.finCoords,pref.mainColour);
            end
            view(3);
            axis tight
            rotate3d(graphics.complete.preview.hWingPlotAxes,'on')
        end
        function ToggleIndividualColours(src,~)
            if src.Value && config.fancyGraphics
                graphics.complete.overview.secondColourText.Enable = 'on';
                graphics.complete.overview.secondColour.Enable = 'on';
                graphics.complete.overview.elevatorColourText.Enable = 'on';
                graphics.complete.overview.elevatorColour.Enable = 'on';
                graphics.complete.overview.finColourText.Enable = 'on';
                graphics.complete.overview.finColour.Enable = 'on';
            else
                graphics.complete.overview.secondColourText.Enable = 'off';
                graphics.complete.overview.secondColour.Enable = 'off';
                graphics.complete.overview.elevatorColourText.Enable = 'off';
                graphics.complete.overview.elevatorColour.Enable = 'off';
                graphics.complete.overview.finColourText.Enable = 'off';
                graphics.complete.overview.finColour.Enable = 'off';
            end
        end
        function GetColour(src,~)
            src.BackgroundColor = uisetcolor(src,sprintf('%s %s %s','Choose',src.UserData,'Colour'));
        end
        function ResizeCompleteGUI(~,~,~)
            currentSize = graphics.f.Position(3:4);
            figureHeight = currentSize(2);
            figureWidth = currentSize(1);
            panelLeft = 1;
            panelHalf = ((((figureWidth/2)-15)/2)-1);
            panelRight = (((figureWidth/2)-15)/2);
            
            % Update sizes.
            graphics.complete.preview.hWingPlotAxes.Position = [10, 10, (figureWidth-20), (figureHeight-50)];
            
            graphics.complete.overview.lPanel.Position = [10 45 ((figureWidth/2)-15) (figureHeight-80)];
            graphics.complete.overview.fileExportText.Position = [panelLeft (figureHeight - 120) panelHalf 19];
            graphics.complete.overview.fileExport.Position = [panelRight (figureHeight - 120) panelHalf 19];
            
            graphics.complete.overview.rPanel.Position = [((figureWidth/2)+5) 45 ((figureWidth/2)-15) (figureHeight-80)];
            graphics.complete.overview.individualColoursCheckbox.Position = [10 (figureHeight-125) (((figureWidth/2)-15)-20) 15];
            graphics.complete.overview.mainColourText.Position = [panelLeft,(figureHeight-160),panelHalf,15];
            graphics.complete.overview.mainColour.Position = [panelRight,(figureHeight-165),33,25];
            graphics.complete.overview.secondColourText.Position = [panelLeft,(figureHeight-195),panelHalf,15];
            graphics.complete.overview.secondColour.Position = [panelRight,(figureHeight-200),33,25];
            graphics.complete.overview.elevatorColourText.Position = [panelLeft,(figureHeight-230),panelHalf,15];
            graphics.complete.overview.elevatorColour.Position = [panelRight,(figureHeight-235),33,25];
            graphics.complete.overview.finColourText.Position = [panelLeft,(figureHeight-265),panelHalf,15];
            graphics.complete.overview.finColour.Position = [panelRight,(figureHeight-270),33,25];
            graphics.complete.overview.UpdateButton.Position = [((((figureWidth/2)-15)/2)-50) 10 100 25];
            graphics.complete.overview.CloseButton.Position = [(figureWidth-110) 10 100 25];
            
        end
    end

    function DrawConflictGuiLeg(thisFoil,otherFoil)
        
        graphics.f2 = figure(...
            'Visible','off',...
            'Position',[figureX,figureY,figureWidth,figureHeight],...
            'NumberTitle','off',...
            'Name',sprintf('%s %s %s',thisFoil.name,localisation.gui.conflictTitle,version),...
            'MenuBar','none');
        set(graphics.f2,'SizeChangedFcn',@UpdateSize);
        
        graphics.conflict.hConflictText = uicontrol(...
            'Style','text',...
            'HorizontalAlignment','left',...
            'String',sprintf('%s',localisation.gui.conflictText),...
            'Position', [10 (figureHeight-55) (figureWidth-20) 45]);
        
        graphics.conflict.hLeftPanel = uipanel(...
            'Title',otherFoil.filename,...
            'FontSize',10,...
            'FontName','FixedWidth',...
            'Units','pixels',...
            'FontWeight','bold',...
            'Position',[10 45 ((figureWidth/2)-15) (figureHeight-110)]);
        
        graphics.conflict.hLeftName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.aerofoilName),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-160) 100 25]);
        
        graphics.conflict.hLeftFoilName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'Units','pixels',...
            'HorizontalAlignment','left',...
            'String',otherFoil.name,...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-160) 100 25]);
        
        graphics.conflict.hLeftPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.folder),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-185) 100 25]);
        
        graphics.conflict.hLeftFoilPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',extractAfter(otherFoil.folder,[rootFolder,'\']),...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-185) 100 25]);
        
        graphics.conflict.hLeftFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.fileFormat),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-210) 100 25]);
        
        graphics.conflict.hLeftFoilFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',otherFoil.format,...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-210) 100 25]);
        
        graphics.conflict.hLeftPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.numberPoints),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-235) 100 25]);
        
        graphics.conflict.hLeftFoilPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',num2str(otherFoil.numPoints(1)),...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-235) 100 25]);
        
        graphics.conflict.hLeftCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.sampleCoords),...
            'Position',[((((figureWidth/2)-15)/2)-110) (figureHeight-260) 110 25]);
        
        graphics.conflict.hLeftFoilCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hLeftPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',sprintf('%f, %f\n%f, %f\n%f, %f\n%f, %f\n%f, %f',otherFoil.coords(1,1),otherFoil.coords(1,2),otherFoil.coords(2,1),otherFoil.coords(2,2),otherFoil.coords(3,1),otherFoil.coords(3,2),otherFoil.coords(4,1),otherFoil.coords(4,2),otherFoil.coords(5,1),otherFoil.coords(5,2)),...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-310) 105 75]);
        
        graphics.conflict.hRightPanel = uipanel(...
            'Title',thisFoil.filename,...
            'FontSize',10,...
            'FontName','FixedWidth',...
            'Units','pixels',...
            'FontWeight','bold',...
            'Position',[((figureWidth/2)+5) 45 ((figureWidth/2)-15) (figureHeight-110)]);
        
        graphics.conflict.hRightName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.aerofoilName),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-160) 100 25]);
        
        graphics.conflict.hRightFoilName = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'Units','pixels',...
            'HorizontalAlignment','left',...
            'String',thisFoil.name,...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-160) 100 25]);
        
        graphics.conflict.hRightPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.folder),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-185) 100 25]);
        
        graphics.conflict.hRightFoilPath = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',extractAfter(thisFoil.folder,[rootFolder,'\']),...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-185) 100 25]);
        
        graphics.conflict.hRightFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.fileFormat),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-210) 100 25]);
        
        graphics.conflict.hRightFoilFormat = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',thisFoil.format,...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-210) 100 25]);
        
        graphics.conflict.hRightPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.numberPoints),...
            'Position',[((((figureWidth/2)-15)/2)-100) (figureHeight-235) 100 25]);
        
        graphics.conflict.hRightFoilPointNum = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',num2str(thisFoil.numPoints(1)),...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-235) 100 25]);
        
        graphics.conflict.hRightCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','right',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.sampleCoords),...
            'Position',[((((figureWidth/2)-15)/2)-110) (figureHeight-260) 110 25]);
        
        graphics.conflict.hRightFoilCoords = uicontrol(...
            'Style','text',...
            'Parent',graphics.conflict.hRightPanel,...
            'HorizontalAlignment','left',...
            'Units','pixels',...
            'String',sprintf('%f, %f\n%f, %f\n%f, %f\n%f, %f\n%f, %f',thisFoil.coords(1,1),thisFoil.coords(1,2),thisFoil.coords(2,1),thisFoil.coords(2,2),thisFoil.coords(3,1),thisFoil.coords(3,2),thisFoil.coords(4,1),thisFoil.coords(4,2),thisFoil.coords(5,1),thisFoil.coords(5,2)),...
            'Position',[(((figureWidth/2)-15)/2) (figureHeight-310) 105 75]);
        
        graphics.conflict.hOpenDatButton = uicontrol(...
            'Style','pushbutton',...
            'Parent',graphics.f2,...
            'Callback',@OpenDat,...
            'String',sprintf('%s',localisation.gui.openDatFolder),...
            'Position',[(figureWidth-330) 10 100 25]);
        
        graphics.conflict.hReloadButton = uicontrol(...
            'Style','pushbutton',...
            'Parent',graphics.f2,...
            'Callback',@Reload,...
            'String',sprintf('%s',localisation.gui.reload),...
            'Position',[(figureWidth-220) 10 100 25]);
        
        graphics.conflict.hCloseButton = uicontrol(...
            'Style','pushbutton',...
            'Parent',graphics.f2,...
            'String',sprintf('%s',localisation.gui.close),...
            'Callback',@Close,...
            'Position',[(figureWidth-110) 10 100 25]);
        
        % Show bounds of objects for debugging.
        if showBounds
            fields = fieldnames(graphics.conflict);
            for i = 1:numel(fields)
                if strcmp(graphics.conflict.(fields{i}).Type,'uicontrol')
                    graphics.conflict.(fields{i}).BackgroundColor = [0 1 0];
                end
            end
        end
        
        graphics.conflict.f2.Visible = 'on';
        
        function Close(~,~,~)
            close(graphics.f2);
        end
        function OpenDat(~,~,~)
            winopen(datFolder);
            uiresume
        end
        function Reload(~,~,~)
            close
            UpdateDatMatrix;
        end
        function UpdateSize(~,~,~)
            currentSize = graphics.f2.Position(3:4);
            figureHeight = currentSize(2);
            figureWidth = currentSize(1);
            % Update sizes.
            graphics.conflict.hConflictText.Position = [10 (figureHeight-55) (figureWidth-20) 45];
            graphics.conflict.hLeftPanel.Position = [10 45 ((figureWidth/2)-15) (figureHeight-110)];
            graphics.conflict.hLeftName.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-160) 150 25];
            graphics.conflict.hLeftFoilName.Position = [(((figureWidth/2)-15)/2) (figureHeight-160) 150 25];
            graphics.conflict.hLeftPath.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-185) 150 25];
            graphics.conflict.hLeftFoilPath.Position = [(((figureWidth/2)-15)/2) (figureHeight-185) 150 25];
            graphics.conflict.hLeftFormat.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-210) 150 25];
            graphics.conflict.hLeftFoilFormat.Position = [(((figureWidth/2)-15)/2) (figureHeight-210) 150 25];
            graphics.conflict.hLeftPointNum.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-235) 150 25];
            graphics.conflict.hLeftFoilPointNum.Position = [(((figureWidth/2)-15)/2) (figureHeight-235) 150 25];
            graphics.conflict.hLeftCoords.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-260) 150 25];
            graphics.conflict.hLeftFoilCoords.Position = [(((figureWidth/2)-15)/2) (figureHeight-310) 150 75];
            graphics.conflict.hRightPanel.Position = [((figureWidth/2)+5) 45 ((figureWidth/2)-15) (figureHeight-110)];
            graphics.conflict.hRightName.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-160) 150 25];
            graphics.conflict.hRightFoilName.Position = [(((figureWidth/2)-15)/2) (figureHeight-160) 150 25];
            graphics.conflict.hRightPath.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-185) 150 25];
            graphics.conflict.hRightFoilPath.Position = [(((figureWidth/2)-15)/2) (figureHeight-185) 150 25];
            graphics.conflict.hRightFormat.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-210) 150 25];
            graphics.conflict.hRightFoilFormat.Position = [(((figureWidth/2)-15)/2) (figureHeight-210) 150 25];
            graphics.conflict.hRightPointNum.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-235) 150 25];
            graphics.conflict.hRightFoilPointNum.Position = [(((figureWidth/2)-15)/2) (figureHeight-235) 150 25];
            graphics.conflict.hRightCoords.Position = [((((figureWidth/2)-15)/2)-150) (figureHeight-260) 150 25];
            graphics.conflict.hRightFoilCoords.Position = [(((figureWidth/2)-15)/2) (figureHeight-310) 150 75];
            graphics.conflict.hOpenDatButton.Position = [(figureWidth-330) 10 100 25];
            graphics.conflict.hReloadButton.Position = [(figureWidth-220) 10 100 25];
            graphics.conflict.hCloseButton.Position = [(figureWidth-110) 10 100 25];
        end
    end

    function GetXmlGuiLeg
        % GETXMLGUI Produces a GUI to get the XML file.
        
        % Error case.
        Choice = 0;
        
        % Create and hide the UI as it is being constructed.
        graphics.f = figure(...
            'Visible','off',...
            'Position',[figureX,figureY,figureWidth,figureHeight],...
            'NumberTitle','off',...
            'Name',sprintf('%s %s',localisation.gui.chooseXmlTitle,funcVersion),...
            'MenuBar','none',...
            'SizeChangedFcn',@ResizeChoiceGUI);
        
        currentSize = graphics.f.Position(3:4);
        figureHeight = currentSize(2);
        figureWidth = currentSize(1);
        panelLeft = 1;
        panelHalf = ((((figureWidth/2)-15)/2)-1);
        panelRight = (((figureWidth/2)-15)/2);
        
        % Load config.
        load(paths.con,'config','pref');
        
        % Test if a file is in config or is just a directory.
        [sections,planeName,planeDes,massStr,spanStr,fileSize,lines,fileName] = PreScanXml(pref.lastXml);
        
        % Construct the components.
        graphics.choice.hChoosePath = uicontrol(...
            'Style','edit',...
            'String',pref.lastXml,...
            'HorizontalAlignment','left',...
            'Callback',@PathUpdated);
        
        graphics.choice.hChooseButton = uicontrol(...
            'Style','pushbutton',...
            'String',sprintf('%s...',localisation.gui.chooseButton),...
            'Callback',@ChoosePath);
        
        % Output options. Called ImportOptions throughout.
        graphics.choice.hImportOptionsPanel = uipanel(...
            'Parent',graphics.f,...
            'Title',sprintf('%s',localisation.gui.outputOptions),...
            'Units','pixels',...
            'FontWeight','bold');
        
        graphics.choice.hLengthText = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','text',...
            'String',sprintf('%s:',localisation.gui.lengthUnits),...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hLengthMenu = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','popupmenu',...
            'String',localisation.units.lengthNames,...
            'Value',find(ismember(localisation.units.lengthNames,pref.lengthUnits)));
        
        graphics.choice.hMassChoiceText = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','text',...
            'String',sprintf('%s:',localisation.gui.massUnits),...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hMassMenu = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','popupmenu',...
            'String',localisation.units.massNames,...
            'Value',find(ismember(localisation.units.massNames,pref.massUnits)));
        
        graphics.choice.hShiftSectionsText = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','text',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.shiftSections),...
            'HorizontalAlignment','right');
        
        graphics.choice.hShiftSectionsCheckbox = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','check',...
            'Units','pixels',...
            'Value',config.shiftSections);
        
        graphics.choice.hAutoReloadText = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','text',...
            'Units','pixels',...
            'String',sprintf('%s:',localisation.gui.autoReload),...
            'HorizontalAlignment','right');
        
        graphics.choice.hAutoReloadCheckbox = uicontrol(...
            'Parent',graphics.choice.hImportOptionsPanel,...
            'Style','check',...
            'Units','pixels',...
            'Value',config.autoReload);
        
        % Preview properties.
        graphics.choice.hPreviewOptionsPanel = uipanel(...
            'Parent',graphics.f,...
            'Title',sprintf('%s',localisation.gui.outputPreviewOptions),...
            'Units','pixels',...
            'FontWeight','bold');
        
        graphics.choice.hFancyGraphicsTickbox = uicontrol(...
            'Parent',graphics.choice.hPreviewOptionsPanel,...
            'Style','check',...
            'Value',config.fancyGraphics,...
            'Units','pixels');
        
        graphics.choice.hFancyGraphicsText = uicontrol(...
            'Parent',graphics.choice.hPreviewOptionsPanel,...
            'Style','text',...
            'String','Simple Graphics:',...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hAxisOnTickbox = uicontrol(...
            'Parent',graphics.choice.hPreviewOptionsPanel,...
            'Style','check',...
            'Units','pixels',...
            'Value',config.showAxis);
        
        graphics.choice.hAxisOnText = uicontrol(...
            'Parent',graphics.choice.hPreviewOptionsPanel,...
            'Style','text',...
            'String',sprintf('%s:',localisation.gui.showAxis),...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        % File import preview.
        graphics.choice.hPreviewPanel = uipanel(...
            'Parent',graphics.f,...
            'Title',sprintf('%s',localisation.gui.importPreview),...
            'Units','pixels',...
            'FontWeight','bold');
        
        graphics.choice.hFileNameText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',sprintf('%s:',localisation.gui.filename),...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hFilename = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',fileName,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        graphics.choice.hFileSizeText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',sprintf('%s:',localisation.gui.size),...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hFileSize = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',fileSize,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        graphics.choice.hSectionsText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String','Sections:',...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hSections = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',sections,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        graphics.choice.hPlaneNameText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String','Plane Name:',...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hPlaneName = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',planeName,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        graphics.choice.hDescriptionText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String','Description:',...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hPlaneDescription = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',planeDes,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        graphics.choice.hMassText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String','Mass:',...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hMass = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',massStr,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        graphics.choice.hSpanText = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String','Span:',...
            'Units','pixels',...
            'HorizontalAlignment','right');
        
        graphics.choice.hSpan = uicontrol(...
            'Parent',graphics.choice.hPreviewPanel,...
            'Style','text',...
            'String',spanStr,...
            'Units','pixels',...
            'HorizontalAlignment','left');
        
        % Bottom buttons.
        graphics.choice.hOKButton = uicontrol(...
            'Style','pushbutton',...
            'String',sprintf('%s',localisation.gui.ok),...
            'Callback',@OK);
        
        graphics.choice.hCancelButton = uicontrol(...
            'Style','pushbutton',...
            'String',sprintf('%s',localisation.gui.cancel),...
            'Callback',@Cancel);
        
        % Make the UI visible.
        graphics.f.Visible = 'on';
        
        function ChoosePath(~,~,~)
            [filename,pathname] = uigetfile('*.xml',sprintf('%s',localisation.gui.chooseXml),[rootFolder,'\XML Files\']);
            if ~isequal(filename,0)
                % Set the path to the file.
                graphics.choice.hChoosePath.String = [pathname,filename];
                PathUpdated;
            end
            
            
        end
        function PathUpdated(~,~,~)
            
            % Get the path.
            if strcmp(graphics.choice.hChoosePath.String(end-3:end),'.xml')
                pathEnd = find(graphics.choice.hChoosePath.String == '\',1,'last');
                filename = graphics.choice.hChoosePath.String(pathEnd+1:end);
                pathname = graphics.choice.hChoosePath.String(1:pathEnd);
            else
                pathEnd = find(graphics.choice.hChoosePath.String == '\',1,'last');
                filename = '';
                pathname = graphics.choice.hChoosePath.String(1:pathEnd);
            end
            
            % Get the sections.
            [sections,planeName,planeDes,massStr,spanStr,fileSize,lines,fileName] = PreScanXml([pathname,filename]);
            
            graphics.choice.hFilename.String = fileName;
            graphics.choice.hFileSize.String = fileSize;
            graphics.choice.hSections.String = sections;
            graphics.choice.hPlaneName.String = planeName;
            graphics.choice.hPlaneDescription.String = planeDes;
            graphics.choice.hMass.String = massStr;
            graphics.choice.hSpan.String = spanStr;
            graphics.choice.hSections.Position = [panelRight,(figureHeight-240+((4-lines)*15)),panelHalf,(19+(lines-1)*15)];
            graphics.choice.hPlaneNameText.Position = [panelLeft (figureHeight-285+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hPlaneName.Position = [panelRight (figureHeight-285+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hPlaneDescription.Position = [panelRight (figureHeight-315+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hDescriptionText.Position = [panelLeft (figureHeight-315+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hMassText.Position = [panelLeft (figureHeight-345+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hMass.Position = [panelRight (figureHeight-345+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hSpanText.Position = [panelLeft (figureHeight-375+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hSpan.Position = [panelRight (figureHeight-375+((4-(lines-1))*15)) panelHalf 19];
            
        end
        function Cancel(~,~,~)
            uiresume
            graphics.Choice = 0;
            close(graphics.f)
        end
        function OK(~,~,~)
            Choice = graphics.choice.hChoosePath.String;
            pref.lastXml = graphics.choice.hChoosePath.String;
            config.showAxis = graphics.choice.hAxisOnTickbox.Value;
            config.fancyGraphics = graphics.choice.hFancyGraphicsTickbox.Value;
            config.shiftSections = graphics.choice.hShiftSectionsCheckbox.Value;
            pref.massUnits = localisation.units.massNames{graphics.choice.hMassMenu.Value};
            pref.lengthUnits = localisation.units.lengthNames{graphics.choice.hLengthMenu.Value};
            save(sprintf('%s\\resources\\config.mat',paths.root),'config','pref','-append');
            graphics.showAxis = graphics.choice.hAxisOnTickbox.Value;
            if config.autoReload
                UpdateDatMatrix;
            end
            xmlPath = Choice;
            Kernel;
        end
        function ResizeChoiceGUI(~,~,~)
            currentSize = graphics.f.Position(3:4);
            figureHeight = currentSize(2);
            figureWidth = currentSize(1);
            panelLeft = 1;
            panelHalf = ((((figureWidth/2)-15)/2)-1);
            panelRight = (((figureWidth/2)-15)/2);
            
            % Choice sizes.
            graphics.choice.hChoosePath.Position = [10,(figureHeight-35),(figureWidth-130),25];
            graphics.choice.hChooseButton.Position = [(figureWidth-110),(figureHeight-35),100,25];
            
            graphics.choice.hImportOptionsPanel.Position = [10 125 ((figureWidth/2)-15) (figureHeight-170)];
            graphics.choice.hLengthText.Position = [panelLeft,(figureHeight-214),panelHalf,19];
            graphics.choice.hLengthMenu.Position = [panelRight,(figureHeight-215),110,25];
            graphics.choice.hMassChoiceText.Position = [panelLeft,(figureHeight-244),panelHalf,19];
            graphics.choice.hMassMenu.Position = [panelRight,(figureHeight-245),110,25];
            
            graphics.choice.hShiftSectionsText.Position = [panelLeft,(figureHeight-274),panelHalf,19];
            strCell = textwrap(graphics.choice.hShiftSectionsText,{sprintf('%s:',localisation.gui.shiftSections)});
            graphics.choice.hShiftSectionsText.String = strCell;
            
            graphics.choice.hShiftSectionsCheckbox.Position = [panelRight,(figureHeight-275),25,25];
            
            graphics.choice.hAutoReloadText.Position = [panelLeft,(figureHeight-304),panelHalf,19];
            strCell = textwrap(graphics.choice.hAutoReloadText,{sprintf('%s:',localisation.gui.autoReload)});
            graphics.choice.hAutoReloadText.String = strCell;
            
            graphics.choice.hAutoReloadCheckbox.Position = [panelRight,(figureHeight-305),25,25];
            
            graphics.choice.hPreviewOptionsPanel.Position = [10 45 ((figureWidth/2)-15) 75];
            graphics.choice.hFancyGraphicsTickbox.Position = [panelRight 35 25 25];
            graphics.choice.hFancyGraphicsText.Position = [panelLeft 36 panelHalf 19];
            graphics.choice.hAxisOnTickbox.Position = [panelRight 6 25 25];
            graphics.choice.hAxisOnText.Position = [panelLeft 7 panelHalf 19];
            
            graphics.choice.hPreviewPanel.Position = [((figureWidth/2)+5), 45, ((figureWidth/2)-15) (figureHeight-90)];
            graphics.choice.hFileNameText.Position = [panelLeft,(figureHeight-135),panelHalf,19];
            graphics.choice.hFilename.Position = [panelRight,(figureHeight-135),panelHalf,19];
            graphics.choice.hFileSizeText.Position = [panelLeft,(figureHeight-165),panelHalf,19];
            graphics.choice.hFileSize.Position = [panelRight,(figureHeight-165),panelHalf,19];
            
            graphics.choice.hSectionsText.Position = [panelLeft,(figureHeight-195),panelHalf,19];
            graphics.choice.hSections.Position = [panelRight,(figureHeight-240+((4-lines)*15)),panelHalf,(19+(lines-1)*15)];
            graphics.choice.hPlaneNameText.Position = [panelLeft (figureHeight-285+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hPlaneName.Position = [panelRight (figureHeight-285+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hDescriptionText.Position = [panelLeft (figureHeight-315+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hPlaneDescription.Position = [panelRight (figureHeight-315+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hMassText.Position = [panelLeft (figureHeight-345+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hMass.Position = [panelRight (figureHeight-345+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hSpanText.Position = [panelLeft (figureHeight-375+((4-(lines-1))*15)) panelHalf 19];
            graphics.choice.hSpan.Position = [panelRight (figureHeight-375+((4-(lines-1))*15)) panelHalf 19];
            
            graphics.choice.hOKButton.Position = [(figureWidth-220),10,100,25];
            graphics.choice.hCancelButton.Position = [(figureWidth-110),10,100,25];
        end
    end

    function AddTreeNodes(parent,child)
        
        n = fieldnames(child);
        for i = 1:length(n)
            if ~isstruct(child(1).(n{i}))
                topTree = uitreenode(parent,'Text',n{i},'NodeData',child(1).(n{i}));
            else
                topTree = uitreenode(parent,'Text',n{i});
                if isstruct(child(1).(n{i}))
                    AddTreeNodes(topTree,child.(n{i}));
                end
            end
        end
        
    end

%% == CHANGELOG ===========================================================
% Date        Ver.      Summary
% --------    ------    ---------------------------------------------------
% 07/02/18    Prerel    Completed input conversion from the XML exported
%                       by XFLR to a useable and predictable MATLAB
%                       structure. Errors can be optionally printed to the
%                       console, and the user interface is setup in the
%                       command line. Fixed an issue with loading XML.
%                       Added a basic GUI option. Added TG's main aircraft
%                       code and modified the GUI code to run more
%                       reliably. Began cleanup for a first release to be
%                       workable.
%
% 08/02/18    0.9.3a    Added setup and config options. Removed text
%                       interface applications to streamline code. Improved
%                       error handling for missing tags on point masses.
%                       Adjusted aerofoil loading method to include
%                       preloading of .DAT folder for easier interfacing
%                       and processing of multiple files. Removed the
%                       config option as it had become redundant. Moved to
%                       an entirely .DAT loaded system, able to handle
%                       Selig or Lednicer type .DAT files. Finished and
%                       tested the reload command. Began implementing a
%                       .DAT conflict resolve GUI. Completed migration to
%                       preloading system, there is now no .Dat loading
%                       during calculation. General tidying across the
%                       whole file.
%
% 15/02/18    0.9.4a    Fixed an issue loading Lednicer format .DAT files
%                       into NX, by reversing the second half internally.
%                       Completely rewritten XML unpacking code to work
%                       with the updated version of xml2struct, and
%                       embedded xml2struct as a nested function. Length
%                       modification is temporarily disabled. Convert the
%                       dihedral values in the data structure to lengths of
%                       each section rather than cumulative span values.
%                       Changed the way the code deals with dihedral.
%                       Awaiting confirmation of success. Change the span
%                       values to length of each section for the elevator
%                       and fin sections and made corrections to the data
%                       referencing in the calculations. Corrected and
%                       reenabled length unit conversions and started
%                       backend for GUI enhancements. Change the twist
%                       calculations to twist about quarter chord. Change
%                       the end aerofoil to rotate by the previous dihedral
%                       angle instead of remaining vertical. Change the
%                       order of the coordinates so they are in the correct
%                       isometric view in NX. Implemented the debug,
%                       complete and progress commands, and began working
%                       on the latter two GUIs. Added and linked all GUIs
%                       together to finish the main program. Moved graphics
%                       to a data structure to make global referencing
%                       easier.
%
% 15/02/18    0.9.5a    Masses of bug fixes following extensive testing.
%
% 15/02/18    1.0.0b    Improved graphics in output GUI, changing leading
%                       and trailing edge lines to use exact values rather
%                       than approximations. Further extensive bug fixes
%                       and edge case handlers following testing. Final
%                       tidying for push to Beta release.
%
% 19/02/18    1.0.3b    Modified GUI to show in a single window for the
%                       entire process. General cleanup throughout the
%                       code. Primitive error handling throughout, and
%                       framework for future handling. Moved to using
%                       degrees rather than radians. More bug fixes and
%                       better error handling. Also  adjusted the output
%                       preview window to change size with its parent
%                       window. Adapted all GUIs to resize dynamically with
%                       their figure, and continued debugging. Also
%                       enchanced error handling again.
%
% 20/02/18    1.0.4b    Added the 'silent' command, which runs the program
%                       with no GUI, and take all arguments like a
%                       function, to allow automation of processing large
%                       numbers of files. Further error processing was also
%                       added.
%
% 21/02/18    1.0.5b    Fixed issue with whole-wing twist, as well as
%                       enabling support for the 'Biplane' feature of
%                       XFLR5. Also fixed an issue with wings which did not
%                       start at the origin, as well as a series of further
%                       error handling cases added.
%
% 18/05/18    1.1.1b    Added 'Folder' on the DAT conflict screen. Fixed
%                       the reload command on MATLAB versions before
%                       R2016b. Language support. Adjusted debug command to
%                       throw errors for easier debugging. Added config.mat
%                       generation which saves the preferences of the last
%                       execution of the program. Also adjusted fancy
%                       graphics to do slightly more, the aerofoils are now
%                       coloured. Added dev command, which enables
%                       development features. Fixed an issue with changing
%                       the filename.
%
% ??/??/??    1.2.0     Modified the path input to update the preview if set
%                       manually. Added more detail to the preview, using a
%                       low-level I/O scan of the file. Tidied up the
%                       allocation of GUI sizes to improve draw speeds.
%
% 09/08/18    2.2.0-pre1    Modified handling of file paths for all
%                       systems. Moved to the app designer methods and
%                       functions. Completely changed the folder structure
%                       and the config file contents, 'resources' folder is
%                       now generated and includes all key files. Modified
%                       the completion GUI extensively and completely
%                       removed the progress GUI. Maintained compatibility
%                       with earlier versions of MATLAB, but only just;
%                       back support will be removed in a later release.

end