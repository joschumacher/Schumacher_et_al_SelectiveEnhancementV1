classdef TSBehavior < handle & matlab.mixin.Copyable
    %EYETRACKING Class to preprocess and handle eye tracking data
    %   Detailed explanation goes here
    
    properties
    end
    
    methods (Static)
        
        %% Loading Functions
        function obj = LoadData(animal, refExptNum, basepath, varargin)
            % LOADDATA  Load data relavant to any experiment that uses eye
            % tracking, can be either behavior or passive stim presentation
            %   OBJ = LOADDATA(ANIMAL, REFEXPTNUM, BASEPATH, VARARGIN)
            %       load all data from the experiment folder
            %
            %   Args:
            %       animal: [string] animal name
            %       refExptNumber: [int] experiment ID
            %       basepath: [str] file path to base data directory
            %
            %   Returns:
            %       obj: [struct] structure containing all relevant eye
            %       tracking data
            
            % set defaults
            obj.metadata.isBehavior = false;
            obj.metadata.isEyeTracking = false;
            obj.metadata.useOffline = false;
            obj.metadata.isSpike2New = 0;
            obj.metadata.rejectUser = 0;
            obj.metadata.whichLick = 'S2';
            obj.data.frameRate = 60;
            % This is a constraint used when aligning Spike2 and log
            % times. 4 eyetracking frames occur for every 1 2P frame, since
            % the 2P scans at 15Hz and our average eye tracking frame rate
            % is 60 Hz, making this a reasonable constraint.
            obj.metadata.timeLockConstraint = 4;
            
            % Pull from keyword arguments
            while ~isempty(varargin)
                switch lower(varargin{1})
                    case 'rejectuser'
                        obj.metadata.rejectUser = varargin{2};
                        
                    case 'whichlick'
                        obj.metadata.whichLick = varargin{2};
                        
                    case 'framerate'
                        obj.data.frameRate = varargin{2};
                        
                    case 'timelockconstraint'
                        obj.metadata.timeLockConstraint = varargin{2};
                        
                    otherwise
                        disp('You have entered an unknown argument.')
                        obj.metadata.(varargin{1}) = varargin{2};
                end
                varargin(1:2) = [];
            end
            
            % Create an object that contains the raw data and some metadata
            obj.metadata.animalID = animal;
            obj.metadata.exptNum = num2str(refExptNum);
            obj.metadata.outcomeNames = {'J', 'H', 'M', 'FA', 'CR', 'NR', ...
                'TE1', 'TE2', 'TE3'};
            
            % Set the path to the main data directory
            exptPath = basepath;
            
            % Get the experiment file number in the right format and create
            % the base data directory name
            refExptNum = strcat('t', num2str(refExptNum, '%05d'));
            basename = fullfile(animal, refExptNum);
            
            % Read from config file
            ETConfigs = ConfigurationParser.ReadEyeTrackingParamConfig();
            
            % Set the data save paths
            savePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.dataSavePath, ...
                'exptpath', exptPath, 'basename', basename, ...
                'animal', animal, 'exptnum', refExptNum);
            obj.metadata.savePath = fullfile(savePath);
            
            figPath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.figureSavePath, ...
                'exptpath', exptPath, 'basename', basename);
            obj.metadata.figPath = fullfile(figPath);
            
            % Start setting paths to the files we want to load
            behaviorPath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.path, ...
                'exptpath', exptPath, 'basename', basename);
            obj.metadata.behaviorPath = fullfile(behaviorPath);
            obj.metadata.stimTimesPath = fullfile(exptPath, basename, ...
                ETConfigs.stimTimes);
            obj.metadata.stimOnTimesPath = fullfile(exptPath, basename,...
                ETConfigs.stimOnTimes);
            obj.metadata.frameTriggerPath = fullfile(exptPath, basename, ...
                ETConfigs.frameTrigger);
            obj.metadata.twoPhotonTimesPath = fullfile(exptPath, basename,...
                ETConfigs.twoPhotonTimes);
            obj.metadata.lickTimesPath = fullfile(exptPath, basename, ...
                ETConfigs.lickTimes);
            
            % Find the behavior data in the base directory using a
            % recursive search for the summary file. If that file doesn't
            % exists, then we are in a passive viewing paradigm
            relPath = TSBehavior.RecursiveDirSearch(behaviorPath, ...
                '*summary.txt');
            if isempty(relPath)
                relPath = TSBehavior.RecursiveDirSearch(behaviorPath, ...
                    '*abs_stim_on_times.txt');
            end
            
            % Now we know the relative path, so set the subdirectory paths.
            obj.metadata.logFilePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.log, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            obj.metadata.summaryFilePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.summary, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            obj.metadata.settingsFilePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.settings, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            obj.metadata.eyeDataFilePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.eyeData, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            obj.metadata.convEyeDataFilePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.convEyeData, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            obj.metadata.ffSettingsFilePath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.ffSettings, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            obj.metadata.passiveStimTimesPath = ConfigurationParser.ReplaceFieldInPath(ETConfigs.passiveStimTimes, ...
                'exptpath', exptPath, 'basename', basename, ...
                'relpath', relPath);
            
            % We know we have a bunch of relative paths with * wildcards in
            % them. Let's fix that.
            fields = fieldnames(obj.metadata);
            for f = 1:length(fields)
                if islogical(obj.metadata.(fields{f})) || ...
                        isfloat(obj.metadata.(fields{f})) || ...
                        iscell(obj.metadata.(fields{f}))
                    % pass
                else
                    fname = dir(obj.metadata.(fields{f}));
                    if ~isempty(fname) && ...
                            ~isempty(strfind(obj.metadata.(fields{f}), '*'))
                        newPath = strsplit(obj.metadata.(fields{f}), '/');
                        obj.metadata.(fields{f}) = '';
                        
                        % Compensate for potentially two eye tracking files
                        if length(fname) > 1
                            obj.metadata.(fields{f}) = fullfile(newPath{1:end-1}, ...
                                fname(end).name);
                        else
                            obj.metadata.(fields{f}) = fullfile(newPath{1:end-1}, ...
                                fname.name);
                        end
                        
                    elseif isempty(fname) && ~(strcmp(fields{f}, 'animalID') || ...
                            strcmp(fields{f}, 'exptNum')  || ...
                            strcmp(fields{f}, 'savePath') || ...
                            strcmp(fields{f}, 'figPath')  || ...
                            strcmp(fields{f}, 'whichLick'))
                        obj.metadata.(fields{f}) = '';
                        
                    elseif strcmp(fields{f}, 'animalID') || ...
                            strcmp(fields{f}, 'exptNum')
                        % pass
                        
                    elseif ~isstring(obj.metadata.(fields{f}))
                        % pass
                    end
                end
            end
            
            % We want to see if the summary file actually exists,
            % otherwise this is a stupid exercise in futility
            if isempty(dir(obj.metadata.summaryFilePath))
                % We're out of luck, return empty handed
                obj.metadata.isBehavior = false;
                fprintf('This is a passive presentation experiment.\n')
            else
                % This is indeed an eye tracking experiment
                obj.metadata.isBehavior = true;
                fprintf('This is a behavior experiment.\n')
            end
            
            
            % We want to see if the eye tracking files actually exist,
            % otherwise this is a stupid exercise in futility
            if isempty(dir(obj.metadata.eyeDataFilePath))
                % We're out of luck, return empty handed
                obj.metadata.isEyeTracking = false;
                fprintf('Only processing stims, not eye tracking data.\n')
            else
                % This is indeed an eye tracking experiment
                obj.metadata.isEyeTracking = true;
                fprintf('Processing stims and eye tracking data.\n')
            end
            
            % Now that we have paths and booleans, let's start loading our
            % data into one big structure.
            obj = TSBehavior.ReadTextFiles(obj, 'twophotontimes', ...
                obj.metadata.twoPhotonTimesPath);
            obj = TSBehavior.ReadTextFiles(obj, 'frametrigger', ...
                obj.metadata.frameTriggerPath);
            obj = TSBehavior.ReadTextFiles(obj, 'stimontimes', ...
                obj.metadata.stimOnTimesPath);
            
            % Perform a check to see if we need to load the stimtimes.txt
            % instead of just stimontimes.txt
            if ~isempty(obj.data.stimID)
                if obj.data.stimID(1) == 0
                    obj.data.stimOn(1) = [];
                    obj.data.stimID(1) = [];
                end
                
                obj = TSBehavior.ReadTextFiles(obj, 'stimtimes', ...
                    obj.metadata.stimTimesPath);
            end
            
            % We have files loaded that are relevant to both behavior and
            % passive experiments. Let's check the files to see which one
            % this is.
            if obj.metadata.isBehavior
                % Load the behavior data
                obj = TSBehavior.ReadTextFiles(obj, 'ffSettings', ...
                    obj.metadata.ffSettingsFilePath);
                obj = TSBehavior.ReadTextFiles(obj, 'log', ...
                    obj.metadata.logFilePath);
                obj = TSBehavior.ReadTextFiles(obj, 'settings', ...
                    obj.metadata.settingsFilePath);
                
            else
                obj = TSBehavior.ReadTextFiles(obj, 'passivestimtimes', ...
                    obj.metadata.passiveStimTimesPath);
            end
            
            % We want the Spike2 lick times file if it's available,
            % otherwise we can throw an error if the user says they
            % want it specifically, but it doesn't exist.
            if ~isempty(obj.metadata.lickTimesPath)
                obj = TSBehavior.ReadTextFiles(obj, 'licktimes', ...
                    obj.metadata.lickTimesPath);
            else
                if strcmp(obj.metadata.whichLick, 'S2')
                    error('EyeTracking:lickFileError', ...
                        ['You must rerun the Spike2 data to get', ...
                        ' the Spike2 lick times.'])
                else
                    warning('Relying on log file lick times.\n')
                end
            end
            
            % Let's check to see if we have a converted eye tracking file.
            % Occasionally one of these will exist because the eye tracking
            % was run post-hoc, and the video encoding messed up,
            % requiring some conversion to a different codec.
            if obj.metadata.isEyeTracking
                if ~isempty(obj.metadata.convEyeDataFilePath)
                    fprintf('Using offline eye tracking data.\n')
                    obj.metadata.useOffline = true;
                    obj.data.eyeData = TSBehavior.ReadTextFiles(obj, 'eyedata', ...
                        obj.metadata.eyeDataFilePath);
                    obj.data.offEye = TSBehavior.ReadTextFiles(obj, 'eyedata', ...
                        obj.metadata.convEyeDataFilePath);
                    obj.data.roi = obj.data.eyeData.roi;
                    obj.data.eyeData = rmfield(obj.data.eyeData, 'roi');
                    obj.data.offEye = rmfield(obj.data.offEye, 'roi');
                else
                    fprintf('Using online eye tracking data.\n')
                    obj.metadata.useOffline = false;
                    obj.data.eyeData = TSBehavior.ReadTextFiles(obj, 'eyedata', ...
                        obj.metadata.eyeDataFilePath);
                    obj.data.roi = obj.data.eyeData.roi;
                    obj.data.eyeData = rmfield(obj.data.eyeData, 'roi');
                end
            end
        end
        
        function relativePath = RecursiveDirSearch(basePath, file)
            % RECURSIVEDIRSERCH  This recrusive search uses a nested
            % function so we can keep track of only the subdirectories we
            % use to find the correct file paths. All we want is the
            % relative path to the relevant subdirectory so we can set the
            % paths correctly in the config file.
            %
            %   RELATIVEPATH = RECURSIVEDIRSERCH(BASEPATH, FILE)
            %
            %   Args:
            %       basepath: [str] file path to base data directory
            %       file: [str] a filename (can contrain * wildcard)
            %
            %   Returns:
            %       relativepath: [str] the path containing the
            %       subdirectory where the file is located
            
            fpath = DirSearch(basePath, file);
            if ~isempty(fpath)
                relativePath = fpath(length(basePath)+2:end);
            else
                relativePath = fpath;
            end
            
            function date = CreationDate(file)
                [~,str] = dos(['dir ', file]);
                rgx = '(\d{4}\.\d{2}\.\d{2}\.\s+\d{2}:\d{2})\s+\d+\s+([^\n]+)';
                tkn = regexp(str,rgx,'tokens');
                date = tkn{1};
            end
            
            % This is the nested function that actually does the searching
            function p = DirSearch(path, file)
                % Get directory structure
                dirinfo = dir(path);
                % remove non-directories
                dirinfo(~[dirinfo.isdir]) = [];
                % Remove references to '.' and '..'
                dirinfo = dirinfo(~ismember({dirinfo.name},{'.','..'}));
                p = '';
                
                for K = 1:length(dirinfo)
                    thisdir = dirinfo(K).name;
                    fullpath = fullfile(path, thisdir);
                    
                    if isempty(dir(fullfile(fullpath, file))) == 0
                        % yay we found the file.
                        p = fullpath;
                        % Get the creation date
                        % date = CreationDate(p);
                        % Return to the loop
                        return;
                    else
                        % If we didn't find the file, recursively search
                        p = DirSearch(fullpath, file);
                    end
                    
                    % Since we're no longer infinitely recursing,
                    % break the loop
                    break;
                end
            end
            
        end
        
        function obj = ReadEyeDataFile(file)
            % READEYEDATAFILE Reads the eye tracking data file
            %   OBJ = READEYEDATAFILE(FILE)
            %
            %   Args:
            %       file: [str]: path to the eye data file
            %
            %   Returns:
            %       obj: [struct] structure containing the eye tracking data
            
            % Read space seperated values, but also extract the weird ROI
            % header
            data = importdata(file, ' ');
            
            % Okay, due to poor choices when programming this in Python
            % originally, we're stuck with a kinda BS little trick that
            % will get things into the correct format for us. Bear with me.
            roi = char(data.textdata(1,1));
            obj.roi = reshape(str2double(regexp(roi(6:end),...
                '-?\d+\.?\d*|-?\d*\.?\d+',...
                'match')), [2,2])';
            
            % Now we want to add all of the fields from the data into the
            % object
            h = data.colheaders;
            for f = 1:length(h)
                if strcmp(h{f}, 'pupil_position_x,')
                    h{f} = 'pupil_position_x';
                end
                obj.(h{f}) = data.data(:,f)';
            end
        end
        
        function obj = ReadLogFile(obj, file)
            % READLOGFILE Reads the eye tracking log file
            %   OBJ = READLOGFILE(FILEPATH)
            %
            %   Args:
            %       file: [str]: path to the eye data file
            %
            %   Returns:
            %       obj: [struct] structure containing the log file data
            
            obj.data.logTime = [];
            obj.data.logFlag = {};
            f1 = fopen(file);
            line = fgetl(f1);
            while ischar(line)
                l = strsplit(line, ' ');
                obj.data.logTime(end+1) = str2double(char(l{end}));
                obj.data.logFlag{end+1} = strjoin(l(1:end-1));
                line = fgetl(f1);
            end
            
            fclose(f1);
        end
        
        function obj = ReadStimTimesFile(obj, file)
            % READSTIMTIMESFILE Reads the eye tracking stim times file.
            % This overwrites the stimID and stimOn fields of the data set.
            
            %   OBJ = READSTIMTIMESFILE(OBJ, FILE)
            %
            %   Args:
            %       file: [str]: path to the stimtimes.txt file
            %
            %   Returns:
            %       obj: [struct] structure containing the stim file data
            
            obj.data.stimID = [];
            obj.data.stimOn = [];
            obj.data.stimOff = [];
            f1 = fopen(file);
            line = fgetl(f1);
            i = 1;
            while ischar(line)
                l = strsplit(line, ' ');
                
                if length(l) > 3 && ~obj.metadata.isBehavior
                    % Passive case
                    obj.data.stimID(end+1) = str2double(l(1));
                    obj.data.stimOn(end+1) = str2double(l(2));
                    obj.data.stimOff(end+1) = str2double(l(end));
                elseif length(l) < 3 && length(l) > 1 && obj.metadata.isBehavior
                    % Behavior case
                    obj.data.stimID(end+1) = str2double(l{1});
                    obj.data.stimOn(end+1) = str2double(l{end});
                else
                    % pass
                end
                
                
                i = i + 1;
                line = fgetl(f1);
                
            end
            
            fclose(f1);
            
            % The first line of this file is sometimes duplicated for some
            % reason. Remove it.
            if obj.data.stimID(1) == 1 && obj.data.stimID(2) == 1
                obj.data.stimID(1) = [];
                obj.data.stimOn(1) = [];
            end
            
            % We need to check if this is a new spike2 recording with
            % updated flags.
            if obj.metadata.isBehavior && max(obj.data.stimID) > 30
                obj.metadata.isSpike2New = 1;
            end
        end
        
        function obj = ReadSettingsFile(obj, file)
            % READSETTINGSFILE Reads the eye tracking stim times file.
            % This overwrites the stimID and stimOn fields of the data set.
            
            %   OBJ = READSTIMTIMESFILE(OBJ, FILE)
            %
            %   Args:
            %       file: [str]: path to the stimtimes.txt file
            %
            %   Returns:
            %       obj: [struct] structure containing the stim file data
            
            f1 = fopen(file);
            line = fgetl(f1);
            while ischar(line)
                l = strsplit(line, ' ');
                label = l{1};
                if strcmp(label, 'sPlusOrientations') || ...
                        strcmp(label, 'sMinusOrientations') || ...
                        strcmp(label, 'airPuffMode')
                    
                    evalc(strcat('obj.data.', line));
                    
                end
                line = fgetl(f1);
                
            end
            
            fclose(f1);
        end
        
        function obj = ReadTextFiles(obj, handle, filepath)
            % READTEXTFILES A generic function that uses the passed handle
            % to evaluat  e how to load the specified file. The handle is
            % then used a the field name in the data structure
            %
            %   Args:
            %       obj: [struct] The data structure
            %       handle: [string] the fields name for the saved data
            %       filepath: [string] path to the file to load
            %   Returns:
            %       obj: [struct] updated data structure
            
            % Reads in arbitrary text files with some handle and assigns
            % them as new fields in the obj structure using the handle
            if isempty(filepath)
                return
            end
            
            switch handle
                
                case 'eyedata'
                    % This will handle the eye tracking data by itself.
                    % It's just wrapping the function
                    obj = TSBehavior.ReadEyeDataFile(filepath);
                    
                case 'log'
                    % This will handle the log file by itself.
                    % It's just wrapping the function
                    obj = TSBehavior.ReadLogFile(obj, filepath);
                    
                case 'ffSettings'
                    % Read from the feature finder file
                    data = importdata(filepath,' ');
                    h = data.rowheaders;
                    for f = 1:length(h)
                        obj.metadata.(handle).(h{f}) = data.data(f);
                    end
                    
                case 'stimontimes'
                    s = load(filepath);
                    obj.data.stimOn = s(2:2:length(s));
                    obj.data.stimID = s(1:2:length(s));
                    
                case 'stimtimes'
                    obj = TSBehavior.ReadStimTimesFile(obj, filepath);
                    
                case 'passivestimtimes'
                    data = importdata(filepath, ' ');
                    obj.data.logFlag = data.data(:,1)';
                    obj.data.logTime = data.data(:,2)';
                    
                case 'settings'
                    obj = TSBehavior.ReadSettingsFile(obj, filepath);
                    
                otherwise
                    data = load(filepath);
                    obj.data.(handle) = data;
            end
        end
        
        %% Preprocessing Functions
        function obj = ReplaceOnlineOfflineTimes(obj)
            % REPLACEONLINEOFFLINEFRAMETIMES Swaps the online, CPU-clocked
            % timestamps from the eye tracking data with the offline
            % processed timestamps when using offline eye tracking data/.
            %
            %   Args:
            %       obj: [struct] The eyeData structure
            %   Returns:
            %       obj: [struct] updated eyeData structure
            
            % All we want to do here is replace the frame times recorded
            % from offline analysis with the PC time recorded during online
            % analysis
            
            % First, check the length of the data to see if things are
            % aligned. Typically, the offline analysis get a few more
            % frames than online
            online = obj.data.eyeData;
            offline = obj.data.offEye;
            frameDiff = online.frame_number(end) - offline.frame_number(end);
            fields = fieldnames(online);
            
            if frameDiff > 0
                % Online eye data has more frames than offline data
                for f = 1:length(fields)
                    online.(fields{f}) = online.(fields{f})(1:end-frameDiff);
                end
                
            elseif frameDiff < 0
                % Offline eye data has more frames than online data
                for f = 1:length(fields)
                    offline.(fields{f}) = offline.(fields{f})(1:end+frameDiff);
                end
                
            else
                % Do nothing as they are the same length
            end
            
            % Replace offline time stamps with online to keep CPU time
            offline = rmfield(offline, 'timestamp');
            offline.timestamp = online.timestamp;
            
            % Since we generally think of the offline data as better, keep
            % it and discard the online data
            obj.data = rmfield(obj.data, 'offEye');
            obj.data = rmfield(obj.data, 'eyeData');
            obj.data.eyeData = offline;
        end
        
        function stims = LookupStimCodes(s2_stim_codes, isBehavior, ...
                animalID, isNew)
            % LOOKUPSTIMCODES Matches Spike2 stim codes to their
            % orientation
            %   STIMS = LOOKUPSTIMCODES(S2_STIM_CODES, ISBEHAVIOR, ANIMALID)
            %
            %   Args:
            %       s2_stim_codes: [array]: spike2 stim codes
            %       isBehavior: [bool]
            %       animalID: [str] animal name
            %
            %   Returns:
            %       stims: [array] the orienation (in degrees) matched to
            %       the stim codes provided
            
            num_stims = length(unique(s2_stim_codes));
            stims = [];
            
            if ~isBehavior
                % Passive viewing
                if num_stims > 17
                    if strcmp(animalID, 'baby')
                        % Pulled from baby's stim file
                        atemp = [117.5, 120.0, 122.5, 125.0, 127.5, 130.0, ...
                            132.5, 135.0, 137.5, 140.0, 142.5, 145.0, ...
                            147.5, 150.0, 152.5, 155.0, 157.5, 160.0, ...
                            162.5, 165, 167.5, 170, 172.5, 175.0, 177.5, ...
                            180.0];
                        btemp = [65.0, 67.5, 70.0, 72.5, 7.05, 77.5, 80.0, ...
                            82.5, 85.0, 87.5, 90.0, 92.5, 95.0, 97.5, 100.0, ...
                            102.5, 105.0, 107.5, 110.0, 112.5, 115.0];
                        ctemp = [0.0, 11.25, 22.5, 33.75, 45.0, 56.25, 67.5, ...
                            78.75, 90.0, 101.25, 112.5, 123.75, 135.0, 146.25, ...
                            157.5, 168.75];
                        dtemp = [20.0, 22.5, 25.0, 27.5, 30.0, 32.5, 3.05, ...
                            37.5, 40.0, 42.5, 45.0, 47.5, 50.0, 52.5, 55.0, ...
                            57.5, 60.0, 62.5];
                        stims = horzcat(atemp, btemp, ctemp, dtemp);
                        
                    else
                        % pulled from Qbert stim file
                        numOrientations = 72;
                        stims = linspace(0.0, 180, numOrientations+1);
                        stims = stims(1:end-1);
                    end
                    
                elseif num_stims <= 17
                    % If drifting, the animal doesn't matter
                    stims = linspace(0.0, 180, 18);
                end
                
                % Note that a blank stim is always presented. We must add
                % another placeholder angle for a blank stim. This is always
                % the highest index. I'll represent this as angle 101010.0
                stims(end+1) = 101010;
                
            else
                % Human readable stim code list
                if ~isNew
                    stims = {'TIMEOUT', 'INIT', 'DELAY', 'GRAY', 'SPLUS', ...
                        'SMINUS', 'REWARD', 'BLACK_SCREEN', 'GRAY_SCREEN', ...
                        'SPLUS_SCREEN', 'SMINUS_SCREEN', 'GRATING_SCREEN', ...
                        'USER_COMMAND', 'REWARD_GIVEN', 'AIR_PUFF'};
                else
                    stims = {'TIMEOUT', 'INIT', 'DELAY', 'GRAY', 'SPLUS', ...
                        'SMINUS', 'REWARD', 'BLACK_SCREEN', 'GRAY_SCREEN', ...
                        'SPLUS_SCREEN', 'SMINUS_SCREEN', 'GRATING_SCREEN', ...
                        'USER_COMMAND', 'REWARD_GIVEN', 'AIR_PUFF', ...
                        'USER_TRIAL', 'LICK_OFF', 'LICK_ON', 'FAIL_PUFF', ...
                        'HINT', 'CORRECT_REWARD'};
                end
            end
        end
        
        %% Passive Functions
        function data = AlignPassiveTimes(data, inclEye)
            % ALIGNPASSIVETIMESINCLEYE Accounts for differences between the
            % Spike2 and CPU clocks, in order to get everything into Spike2
            % time.
            %
            %   Args:
            %       data: [struct] The data structure
            %   Returns:
            %       data: [struct] updated data structure
            
            % Now we have a couple of different time stamps to work with.
            % Frames and stim start times are locked to PC time (data.timestamp,
            % sdata.logTime), and 2P time, stim start, and stop time are
            % also locked to Spike2's internal time (data.stimOn, ).
            
            % Normalize spike2 time - now we have the start and end of each
            % stim relative to the start of the 2P scanning
            tpTime0 = data.twophotontimes(1);
            s2Time0 = data.stimOn(1);
            [~, OverlapIdx, ~] = FindNearest(data.twophotontimes, ...
                s2Time0);
            s2TimeDiff = tpTime0 - s2Time0;
            
            % Check to see if frames or stims started first (usually it's
            % frames) and normalize to the one that started first. After
            % this step, the eye tracking timestamp times will be normalized
            % in reference to the frame acquisition start in terms of CPU
            % time.
            
            logTime0 = data.logTime(1);
            
            if inclEye
                % Only if we're doing eye tracking
                frameTime0 = data.eyeData.timestamp(1);
                frameStimDiff = frameTime0 - logTime0;
                
                if frameStimDiff > 0
                    % Stims started first
                    data.eyeData.timestamp = data.eyeData.timestamp - logTime0;
                    data.logTime = data.logTime - logTime0;
                elseif frameStimDiff < 0
                    % Frames started first
                    data.eyeData.timestamp = data.eyeData.timestamp - frameTime0;
                    data.logTime = data.logTime - frameTime0;
                end
                
            else
                % we only need to worry about log times
                data.logTime = data.logTime - logTime0;
            end
            
            % Here we have an interesting situation. We now have a few
            % different clocks. We consider the 2P times (in Spike2) to be
            % the true clock, so everything else must be in reference to the
            % 2P scans. However, we know that there will be some aberration
            % between the log file's CPU time and the stim time from spike2.
            % Here we check the element-wise difference between those two
            % stimulus lists to get an idea of what the average asynchrony
            % is. I notice that the spike2 times tend to  come before the
            % log times. This is because the spike2 trigger is sent to the
            % DAQ before the log file is updated. Also, the log file has
            % lower temporal resolution since the CPU time is only good to
            % 10ms. However, for our purposes, we will continue to use the
            % Spike 2 times unless there is a gross misalignment (greater
            % than 1 frame at 60 Hz).
            
            % For some reason there's always a weird ending flag in
            % the spike2 data that we can throw out
            if (length(data.logFlag) > length(data.stimID)) && ...
                    isequal(data.logFlag(1:length(data.stimID)), data.stimID)
                data.logFlag = data.logFlag(1:length(data.stimID));
                data.logTime = data.logTime(1:length(data.stimID));
            end
            
            s2Starts = data.stimOn - data.stimOn(1);
            logStarts = data.logTime - data.logTime(1);
            timeDiff = s2Starts - logStarts;
            meanTDiff = mean(timeDiff);
            fr = data.frameRate;
            
            if abs(meanTDiff) <= 1/fr
                fprintf(['Spike2 and log file times aligned within ', ...
                    '1 frame (%0.1f ms).\n'], 1000/fr);
            else
                if inclEye
                    warning(['Trigger times misaligned by more than '...
                        '%0.1f ms (1 frame). Error is %0.0f ms. ', ...
                        'Realigning clocks...\n'], 1000/fr, ...
                        meanTDiff*1000)
                    
                    % Do an iterative clock alignment/time warp
                    data = TSBehavior.ClockCheck(data, data.stimOn, ...
                        data.logTime);
                    
                    % If we deviate from the eye tracking frame rate by
                    % more than 5% when
                    newFR = GetTrialDuration(data.eyeData.timestamp);
                    if newFR > 1/data.frameRate + 0.05/data.frameRate
                        warning(['Clock realignment changed eye ', ...
                            'tracking frame rate to %0.1f FPS.\n'], ...
                            newFR)
                    else
                        disp('Eye tracking clock and Spike2 clock aligned.')
                    end
                    
                    % For a sanity check, see what index the and time the eye
                    % camera starts in reference to the 2P
                    [~, cam2P, ~] = FindNearest(data.twophotontimes, ...
                        data.eyeData.timestamp(1));
                else
                    warning(['Trigger times misaligned by more than '...
                        '%0.1f ms (1 frame). Error is %0.0f ms. ', ...
                        'Relying on Spike2 times.\n'], 1000/fr, ...
                        meanTimeDiff*1000)
                end
            end
            
            % We now have the frame times, and stim times in reference to
            % Spike2 time, with all of it in reference to the start of the
            % 2P. Note that it may happen that the 2P time could be negative
            % in the case where Joe starts the 2P after starting the stims.
        end
        
        function data = GetPassiveBlocks(data, inclEye)
            % GETPASSIVEBLOCKS Finds periods of time surrounding and
            % including the passive stimulus presentations
            %
            %   Args:
            %       data: [struct] The data structure
            %   Returns:
            %       data: [struct] updated data structure
            
            % Get a list of indices that make up the blocks of time we've
            % defined from the spike2 file
            fprintf('Finding stimulus presentation blocks...\n')
            twoPIdxs = zeros(length(data.stimOn), 4);
            eyeIdxs = zeros(length(data.stimOn), 4);
            trialOn = GetTrialDuration(data.stimOn);
            
            for i = 1:length(data.stimOn)
                % Get a dataset where the trial is flanked by two periods
                % of nothing
                on = data.stimOn(i);
                off = data.stimOff(i);
                surroundTime = trialOn - (off - on);
                
                % Get 2P data
                [~, twoPStimStart, ~] = FindNearest(data.twophotontimes, ...
                    on);
                [~, twoPStimEnd, ~] = FindNearest(data.twophotontimes, ...
                    off);
                [~, twoPPre, ~] = FindNearest(data.twophotontimes, ...
                    on - 0.5*surroundTime);
                [~, twoPPost, ~] = FindNearest(data.twophotontimes, ...
                    off + 0.5*surroundTime);
                twoPIdxs(i, :) = [twoPPre, twoPStimStart, twoPStimEnd, twoPPost];
                
                if inclEye
                    % Get eye data
                    [~, eyeStimStart, ~] = FindNearest(data.eyeData.timestamp, ...
                        on);
                    [~, eyeStimEnd, ~] = FindNearest(data.eyeData.timestamp, ...
                        off);
                    [~, eyePre, ~] = FindNearest(data.eyeData.timestamp, ...
                        on - 0.5*surroundTime);
                    [~, eyePost, ~] = FindNearest(data.eyeData.timestamp, ...
                        off + 0.5*surroundTime);
                    eyeIdxs(i, :) = [eyePre, eyeStimStart, eyeStimEnd, eyePost];
                end
            end
            
            % Save data to the main structure
            data.twoPBlocks = twoPIdxs;
            
            if inclEye
                data.eyeBlocks = eyeIdxs;
            else
                data.eyeBlocks = [];
            end
            
        end
        
        %% Behavior Functions
        function data = ExtractBehaviorStates(data, isNew)
            % EXTRACTBEHAVIORSTATESNEW Scrapes the stimID field to assess
            % what states occured during the experiment.
            %
            %   Args:
            %       data: [struct] The data structure
            %   Returns:
            %       data: [struct] updated data structure
            
            % Another pre-processing step requires us to separate state
            % changes from licks in the log file
            
            stateChange = [];
            stateChangeTime = [];
            lick = [];
            lickTime = [];
            oris = [];
            oriTime = [];
            userTrial = [];
            userTrialTime = [];
            airPuff = [];
            airPuffTime = [];
            hints = [];
            hintsTime = [];
            rewards = [];
            rewardsTime = [];
            allFlags = [];
            allTimes = [];
            k = 0;
            
            for i = 1:length(data.logFlag)
                
                if strfind(data.logFlag{i}, 'State')
                    % Record state type
                    type = str2double(data.logFlag{i}(end));
                    ts = data.logTime(i);
                    stateChange(end+1, :) = [k, type];
                    stateChangeTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    k = k+1;
                    
                elseif strfind(data.logFlag{i}, 'Sensors')
                    % Record state type
                    data.serialStart = data.logTime(i);
                    
                elseif strfind(data.logFlag{i}, 'user_reward')
                    % If the user gives a reward
                    type = 80; %changed from 20 to 80 on 6/26/20 debugging with GR
                    ts = data.logTime(i);
                    stateChange(end+1, :) = [k, type];
                    stateChangeTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    k = k + 1;
                    
                elseif strfind(data.logFlag{i}, 'User administered')
                    % If the user gives an air puff
                    type = 21;
                    ts = data.logTime(i);
                    stateChange(end+1, :) = [k, type];
                    stateChangeTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    k = k + 1;
                    
                elseif strfind(data.logFlag{i}, 'User started')
                    % Record state type of user-started trial
                    type = 22;
                    ts = data.logTime(i);
                    userTrial(end+1, :) = [k, type];
                    userTrialTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    if isNew
                        stateChange(end+1, :) = [k, type];
                        stateChangeTime(end+1) = ts;
                    end
                    k = k + 1;
                    
                elseif strfind(data.logFlag{i}, 'Lo')
                    % Lick off
                    type = 30;
                    ts = data.logTime(i);
                    lick(end+1, :) = [k, type];
                    lickTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    k = k + 1;
                    
                elseif strfind(data.logFlag{i}, 'Lx')
                    % Lick on
                    type = 31;
                    ts = data.logTime(i);
                    lick(end+1, :) = [k, type];
                    lickTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    k = k + 1;
                    
                elseif strfind(data.logFlag{i}, 'Puff')
                    % Air puff for failing the trial
                    type = 21; %used to be set to 40, but changed for amidala
                    ts = data.logTime(i);
                    airPuff(end+1, :) = [k, type];
                    airPuffTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    if isNew
                        stateChange(end+1, :) = [k, type];
                        stateChangeTime(end+1) = ts;
                    end
                    k = k+ 1;
                    
                elseif strfind(data.logFlag{i}, 'RL')
                    % Animal gets a hint
                    type = 41;
                    ts = data.logTime(i);
                    hints(end+1, :) = [k, type];
                    hintsTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    if isNew
                        stateChange(end+1, :) = [k, type];
                        stateChangeTime(end+1) = ts;
                    end
                    k = k+ 1;
                    
                elseif strfind(data.logFlag{i}, 'RH')
                    % Animal gets a reqard for getting trial correct
                    type = 50;
                    ts = data.logTime(i);
                    rewards(end+1, :) = [k, type];
                    rewardsTime(end+1) = ts;
                    allFlags(end+1) = type;
                    allTimes(end+1) = ts;
                    if isNew
                        stateChange(end+1, :) = [k, type];
                        stateChangeTime(end+1) = ts;
                    end
                    k = k+ 1;
                    
                elseif strfind(data.logFlag{i}, 'bolus')
                    % Same as getting a trial correct; pass
                    
                elseif strfind(data.logFlag{i}, 'hint')
                    % Same as finding RL; pass
                    
                elseif strfind(data.logFlag{i}, 'sqr') == 1
                    % This is the orientation data for the stimulus. It is
                    % locked to the time of the target or distractor stim
                    % onset
                    
                    ts = data.logTime(i);
                    toks = strsplit(data.logFlag{i}, ' ');
                    ori = str2double(toks{1}(4:end));
                    phase = str2double(toks{2}(3:end));
                    
                    oriTime(end+1) = ts;
                    
                    if any(data.sMinusOrientations(:) == ori)
                        oris(end+1, :) = [5, ori, phase];
                    else
                        oris(end+1, :) = [4, ori, phase];
                    end
                    
                else
                    % pass
                    
                end
            end
            
            % Add each of these new data sets to the structure
            data.logTrigger = stateChange';
            data.logOnTime = stateChangeTime;
            data.licks = lick';
            data.lickTime = lickTime;
            data.ori = oris';
            data.oriTime = oriTime;
            data.logEvents = allFlags;
            data.logEventTime = allTimes;
            
            % This is for backwards compatability of all data sets
            if ~isNew
                data.userTrial = userTrial;
                data.userTrialTime = userTrialTime;
                data.airPuff = airPuff;
                data.airPuffTime = airPuffTime;
                data.hints = hints;
                data.hintsTime = hintsTime;
                data.rewards = rewards;
                data.rewardsTime = rewardsTime;
            end
        end
        
        function data = CorrectStimErrors(data, metadata)
            % CORRECTSTIMERRORS  Assesses if the log and Spike2 files are
            % in agreement, and if not, determines if the correction needs
            % to be made by FixBehavioralTriggersSimple or
            % FixBehavioralTriggersHard
            %
            %   DATA = LOADDATA(DATA, METADATA) Search for errors between
            %   stimulus flags in the log and Spike2 files
            %
            %   Args:
            %       data: [struct] the structure containing all data
            %       relelvant to the experiment
            %       metadata: [struct] experiment ID
            %
            %   Returns:
            %       data: [struct] the data structure with the corrected
            %       logTrigger, stimID, logTime, and stimOn fields
            
            
            % make sure everything lines up again - log file
            [data.logOnTime, logSortIdx] = sort(data.logOnTime, 'ascend');
            data.logTrigger = data.logTrigger(:,logSortIdx);
            
            [data.logEventTime, logSortIdx] = sort(data.logEventTime, 'ascend');
            data.logEvents = data.logEvents(logSortIdx);
            
            % Do the same for the Spike2 data
            [data.stimOn, stimSortIdx] = sort(data.stimOn, 'ascend');
            data.stimID = data.stimID(:,stimSortIdx);
            
            % It looks like there is sometimes a trailing trial
            % initialization - get rid of it.
            while data.logTrigger(2, end) == 1
                data.logFlag(end) = [];
                data.logTrigger(:,end) = [];
                data.logOnTime(end) = [];
            end
            
            while data.stimID(end) == 1 || data.stimID(end) == 10
                data.stimID(end) = [];
                data.stimOn(end) = [];
            end
            
            while data.logEvents(end) == 1
                data.logEvents(end) = [];
                data.logEventTime(end) = [];
            end
            
            % Check to see if Spike2 event logging is the same as what I
            % pulled from the log file.
            if isequal(data.logTrigger(2,:), data.stimID)
                fprintf('Triggers are equivalent. No need to correct.\n');
                
            else
                fprintf('Reconciling trigger errors...\n');
                
                % check to see if the number of elements between the sets is
                % different
                elemDiff = length(data.logTrigger) - length(data.stimID);
                
                % If the same number of elements are present, check to see
                % if any flags are flipped
                if abs(elemDiff) == 0
                    fprintf('Correcting for flipped stim codes (simple)...\n');
                    data = TSBehavior.FixBehavioralTriggersSimple(data);
                    
                    % Check again to see if there is an alignment error
                    if isequal(data.logTrigger(2,:), data.stimID(1,:)) %was data.stimID(2,:), changed for qbert
                        fprintf('Triggers are equivalent. Correction successful.\n');
                    else
                        vv = find(data.logTrigger(2,:) ~= data.stimID, 1);
                        if vv - 5 <= 0 %was < changed 6/15/20
                            logVV = data.logTrigger(2, 1:vv+5);
                            s2VV = data.stimID(1:vv+5);
                        else
                            logVV = data.logTrigger(2, vv-5:vv+5);
                            s2VV = data.stimID(vv-5:vv+5);
                        end
                        logVVT = data.logOnTime(vv);
                        s2VVT = data.stimOn(vv);
                        fprintf('Log file around index %d is %d at time %0.0f \n',...
                            vv, logVV, logVVT);
                        fprintf('Spike2 file around index %d is %d at time %0.0f \n',...
                            vv, s2VV, s2VVT);
                        error('EyeTracking:mismatchError', ...
                            ['Could not reconcile Spike2 and log files triggers. ', ...
                            'Elements differ at index %d\n'], vv);
                    end
                    
                    % Otherwise we have the much bigger problem of dropped
                    % flags.
                else
                    % Attempt to find where the error is
                    fprintf('Flags dropped. Looking for whre they got lost (hard).\n');
                    try
                        [data, nDrops, tDrops] = TSBehavior.FixBehavioralTriggersHard(data);
                    catch
                        error('EyeTracking:recursionError', ...
                            ['Entered large recursion sequence. ', ...
                            'Check your raw data for weirdness.\n'])
                    end
                    
                    % Check again to see if there are differences
                    if isequal(data.logTrigger(2,:), data.stimID)
                        fprintf('Triggers are equivalent. Correction successful.\n');
                        
                        % We want to write where things went wrong to a file.
                        errorFile = fullfile(metadata.behaviorPath, 'trigger_drops.txt');
                        fid = fopen(errorFile, 'wt');
                        fprintf(fid, strcat(num2str(nDrops), ' triggers dropped.\n'));
                        if ~isempty(tDrops)
                            for d = 1:length(nDrops)
                                fprintf(fid, strcat(num2str(tDrops(1)), ' ')) ...
                                    %num2str(tDrops(2)))); %joe commented
                                    %out because of error...
                            end
                        end
                        fclose(fid);
                        
                    else
                        
                         fprintf('Reconciling trigger errors...\n');
                
                % check to see if the number of elements between the sets is
                % different
                elemDiff = length(data.logTrigger) - length(data.stimID);
                
                % If the same number of elements are present, check to see
                % if any flags are flipped
                if abs(elemDiff) == 0
                    fprintf('Correcting for flipped stim codes (simple)...\n');
                    data = TSBehavior.FixBehavioralTriggersSimple(data);
                    
                    % Check again to see if there is an alignment error
                    if isequal(data.logTrigger(2,:), data.stimID(1,:))
                        fprintf('Triggers are equivalent. Correction successful.\n');
                    else
                        vv = find(data.logTrigger(2,:) ~= data.stimID, 1);
                        if vv - 5 < 0
                            logVV = data.logTrigger(2, 1:vv+5);
                            s2VV = data.stimID(1:vv+5);
                        else
                            logVV = data.logTrigger(2, vv-5:vv+5);
                            s2VV = data.stimID(vv-5:vv+5);
                        end
                        logVVT = data.logOnTime(vv);
                        s2VVT = data.stimOn(vv);
                        fprintf('Log file around index %d is %d at time %0.0f \n',...
                            vv, logVV, logVVT);
                        fprintf('Spike2 file around index %d is %d at time %0.0f \n',...
                            vv, s2VV, s2VVT);
                        error('EyeTracking:mismatchError', ...
                            ['Could not reconcile Spike2 and log files triggers. ', ...
                            'Elements differ at index %d\n'], vv);
                    end
%                         vv = find(data.logTrigger(2,:) ~= data.stimID, 1);
%                         if vv - 5 < 0
%                             logVV = data.logTrigger(2, 1:vv+5);
%                             s2VV = data.stimID(1:vv+5);
%                         else
%                             logVV = data.logTrigger(2, vv-5:vv+5);
%                             s2VV = data.stimID(vv-5:vv+5);
%                         end
%                         logVVT = data.logOnTime(vv);
%                         s2VVT = data.stimOn(vv);
%                         fprintf('Log file around index %d is %d at time %0.0f \n',...
%                             vv, logVV, logVVT);
%                         fprintf('Spike2 file around index %d is %d at time %0.0f \n',...
%                             vv, s2VV, s2VVT);
%                         error('EyeTracking:mismatchError', ...
%                             ['Could not reconcile Spike2 and log files triggers. ', ...
%                             'Elements differ at index %d\n'], vv);
                    end
                end
            end
            end
        end
        
        function data = FixBehavioralTriggersSimple(data)
            % FIXBEHAVIORALTRIGGERSSIMPLE  Searches for flipped stim codes
            % in the Spike2 and log files and correct the flag and
            % corresponding time point.
            %
            %   DATA = FIXBEHAVIORALTRIGGERSSIMPLE(DATA) Search for errors
            %   between stimulus flags in the log and Spike2 files
            %
            %   Args:
            %       data: [struct] the structure containing all data
            %       relelvant to the experiment
            %
            %   Returns:
            %       data: [struct] the data structure with the corrected
            %       logTrigger, stimID, logTime, and stimOn fields
            
            s2Trig = data.stimID;
            s2Time = data.stimOn;
            logTrig = data.logTrigger;
            logTime = data.logOnTime;
            
            whereDiff = find(logTrig(2,:) ~= s2Trig);
            swaps = [];
            for i = 1:length(whereDiff)-1
                if whereDiff(i+1) == whereDiff(i)+1
                    swaps(end+1, :) = [whereDiff(i), whereDiff(i+1)];
                end
            end
            
            otherError = [];
            if isempty(swaps)
                otherError = swaps;
            else
                for i = 1:length(whereDiff)
                    if ~ismember(whereDiff(i), swaps)
                        otherError(end+1) = whereDiff(i);
                    end
                end
            end
            
            % Likely there will be some differences, but almost always these
            % are swaps. Correct for them here.
            if ~isempty(swaps)
                for s = 1:size(swaps,1)
                    
                    % Makes things easier to keep track of
                    idx = swaps(s, 1);
                    nextIdx = swaps(s, 2);
                    s2 = s2Trig(idx);
                    s2t = s2Time(idx);
                    s2Next = s2Trig(nextIdx);
                    s2tNext = s2Time(nextIdx);
                    l = logTrig(:,idx);
                    lt = logTime(idx);
                    lNext = logTrig(:,nextIdx);
                    ltNext = logTime(nextIdx);
                    
                    if s2 == lNext(2) && l(2) == s2Next
                        % We've found a swap. Let's check to see if the
                        % times are close together. If they are, we can
                        % simply eliminate the delay period that writes
                        % simultaneously to the spike2 and log files. Set
                        % our cutoff at 1 second. We know a delay must come
                        % before a stim presentation. Since these usually
                        % occur when manually initiating a trial, simply
                        % searching for the delay is enough to align correctly
                        if (s2 == 1 && l(2) == 2) || (s2 == 2 && l(2) == 0) ...
                                || (s2 == 0 && l(2) == 1) || (s2 == 2 && l(2) > 2) ...
                                || (s2 == 3 && l(2) == 0) || (s2 == 4 && l(2) == 0) ...
                                || (s2 == 0 && l(2) == 42) || (s2 == 0 && l(2) == 40)
                            logTrig(:,idx) = lNext;
                            logTrig(:,nextIdx) = l;
                            logTime(idx) = ltNext;
                            logTime(nextIdx) = lt; %was nextIdx
                            
                        elseif (l(2) == 1 && s2 == 2) || (l(2) == 2 && s2 == 0) ...
                                || (l(2) == 0 && s2 == 1) || (l(2) == 2 && s2 > 2) ...
                                || (l(2) == 3 && s2 == 0) || (l(2) == 4 && s2 == 0) ...
                                || (l(2) == 0 && s2 == 42) || (l(2) == 0 && s2 == 40)
                            s2Trig(idx) = s2Next;
                            s2Trig(nextIdx) = s2;
                            s2Time(idx) = s2t;
                            s2Time(nextIdx) = s2tNext;
                        end
                    end
                end
            end
            
            if ~isempty(otherError)
                for i = 1:length(otherError)
                    % This is an aberrant mismatch. Let's see if this is a
                    % repeat of a previous stim code
                    idx = otherError(i);
                    lPrev = logTrig(:,idx-1);
                    l = logTrig(:,idx);
                    lNext = logTrig(:,idx+1);
                    s2Prev = s2Trig(idx-1);
                    s2 = s2Trig(idx);
                    s2Next = s2Trig(idx+1);
                    
                    if (lPrev(2) == s2Prev) && (lNext(2) == s2Next)
                        % Check if it's a random repeat
                        if (l(2) == lPrev(2)) || (l(2) == lNext(2))
                            logTrig(2,idx) = s2Trig(idx);
                        elseif (s2 == s2Prev) || (s2 == s2Next)
                            s2Trig(idx) = logTrig(2, idx);
                        end
                        
                        %rare case where random event codes outside task are
                        %misidentified, doesn't really matter
                        if (l(2)>10)&(s2>10)
                            logTrig(2,idx) = s2Trig(idx);
                        end
                        
                    end
                end
            end
            
            data.stimID = s2Trig;
            data.stimOn = s2Time;
            data.logTrigger = logTrig;
            data.logOnTime = logTime;
        end
        %%
        function [data, numDrop, timeDrop] = FixBehavioralTriggersHard(data)
            % FIXBEHAVIORALTRIGGERSHARD  Searches for dropped stim codes
            % in the Spike2 and log files and correct the flag and
            % corresponding time point using a recursive search.
            %
            %   DATA = FIXBEHAVIORALTRIGGERSHARD(DATA) Search for errors
            %   between stimulus flags in the log and Spike2 files
            %
            %   Args:
            %       data: [struct] the structure containing all data
            %       relelvant to the experiment
            %
            %   Returns:
            %       data: [struct] the data structure with the corrected
            %       logTrigger, stimID, logTime, and stimOn fields
            
            % This is a massive pain in the ass. We are forced to cycle
            % through the entire data set, correcting flips where we can,
            % and then identifying the where the gap is. Once the gap is
            % corrected, we should be able to simply correct flips and
            % aberrant errors.
            
            s2Trig = data.stimID;
            s2Time = data.stimOn;
            logTrig = data.logTrigger;
            logTime = data.logOnTime;
            
            % Number of potentially dropped flags
            numDrop = 0;
            timeDrop = [];
            
            %Recursively search for errors
            [data.stimID, data.stimOn, data.logTrigger, data.logOnTime, ...
                numDrop, timeDrop] = TSBehavior.RecursiveDropSearch(...
                s2Trig, s2Time, ...
                logTrig, logTime, ...
                numDrop, timeDrop);
        end
        
        function data = AlignBehaviorTimes(data, inclEye, isNew, timeConst)
            % ALIGNBEHAVIORTIMES Attempts to align the behavior times
            % between the Spike2 and CPU clocks.
            %
            %   Args:
            %       data: [struct] The data structure
            %       inclEye: [bool] boolean if using eye tracking
            %       isNew: [bool] boolean if using new Spike2 codes
            %   Returns:
            %       data: [struct] updated data structure
            
            % Get the serial start time for the lick/tap sensor. This is
            % out zero time for the CPU/log file clock
            stimTime0 = data.serialStart;
            
            % Prevent dumb mistakes by verifying that trigger data and
            % licking data flags match.
            if ~isNew
                % This find the indices in the log file that contain only
                % triggers found in the spike2 file. This prevents us from
                % having too many mismatch errors
                inS2 = find(ismember(data.logEvents, unique(data.stimID)));
                logEvCopy = data.logEvents;
                logEvTimeCopy = data.logEventTime;
                data.logEvents = data.logEvents(inS2);
                data.logEventTime = data.logEventTime(inS2);
            end
            
            %             if ~isequal(data.logTrigger(2,:), data.stimID)
            %                 error('EyeTracking:mismatchError', ...
            %                       ['Spike2 and log file stims do not match. ', ...
            %                        'Needs manual inspection.\n'])
            %             end
            %
            %             % Check to see if the lick data matches (only if using Spike2
            %             % lick times)
            if isfield(data, 'licktimes')
                %
                %                 % One thing we see fairly regularly is that Spike2 records
                %                 % licks before Shrewdriver even starts, so we'll remove
                %                 % those licks. We also want to be sure that this starts
                %                 % with a lock on (code 31)
                %                 while data.licktimes(1, 2) <= data.stimOn(1)
                %                     [~, lIdx, ~] = FindNearest(data.licktimes(:,2), ...
                %                                                           data.stimOn(1));
                %                     data.licktimes(1:lIdx, :) = [];
                %                 end
                %
                %                 % We should do the same for the log File
                %                 while data.lickTime(1) < data.logOnTime(1)
                %                     data.licks(:,1) = [];
                %                     data.lickTime(1) = [];
                %                     % Correct the logEvents variable
                %                     logEvLicks = find(data.logEvents == 30 | data.logEvents == 31, ...
                %                                       1);
                %                     data.logEvents(logEvLicks) = [];
                %                     data.logEventTime(logEvLicks) = [];
                %                 end
                %
                %                 lickDiff = length(data.licktimes) - length(data.licks);
                %
                %                 if lickDiff > 0
                %                     data.licktimes = data.licktimes(1:length(data.licks),:);
                %                 elseif lickDiff < 0
                %                     data.licks = data.licks(:, ...
                %                                          1:length(data.licktimes));
                %                     data.lickTime = data.lickTime(:, ...
                %                                          1:length(data.licktimes));
                %
                %                     % Correct the logEvents variable
                %                     logEvLicks = find(data.logEvents == 30 | data.logEvents == 31, ...
                %                                       abs(lickDiff), 'last');
                %                     data.logEvents(logEvLicks) = [];
                %                     data.logEventTime(logEvLicks) = [];
                %
                %                 else
                %                     %pass
                %                 end
                %
                %                 if ~isequal(data.licks(2,:), data.licktimes(:,1)')
                %                     error('Spike2 and log file lick flags do not match.')
                %                 end
                %
                %                 % At this point we know all the triggers (and possibly licks)
                %                 % are equivalent, but we need to align the trigger times
                %                 % between the Spike2 and log files, and also the eye tracking
                %                 % data. There may occasionally be CPU clock drift, so we'll do
                %                 % a tedious but necessary correction.
                %
                % Reassemble the stim codes and times into arrays that
                % are in correct temporal order.
                
                % Spike 2 events
                states = horzcat(data.stimID, data.licktimes(:, 1)');
                times = horzcat(data.stimOn, data.licktimes(:, 2)');
                
                % Sort Spike2 events by time
                [data.s2EventTime, sortIdxs] = sort(times, 'ascend');
                data.s2Events = states(sortIdxs);
            else
                data.s2EventTime = data.stimOn;
                data.s2Events = data.stimID;
                data.logEvents = data.logTrigger(2,:);
                data.logEventTime = data.logOnTime;
            end
            
            
            %             % We consider Spike2 to be ground truth, so fix any mistakes
            %             % between the two.
            %             if ~isequal(data.logEvents, data.s2Events)
            %
            %                whereDiff = find(data.logEvents ~= data.s2Events);
            %                swaps = [];
            %
            %                for i = 1:length(whereDiff)-1
            %                    if whereDiff(i+1) == whereDiff(i)+1
            %                        swaps(end+1, :) = [whereDiff(i), whereDiff(i+1)];
            %                    end
            %                end
            %
            %                otherError = [];
            %                for i = 1:length(whereDiff)
            %                    if ~ismember(whereDiff(i), swaps)
            %                        otherError(end+1) = whereDiff(i);
            %                    end
            %                end
            %
            %                % Fix these errors
            %                count = 0;
            %                while ~isempty(swaps) && ~isempty(otherError)
            %                    count = count + 1;
            %                    if count > 300
            %                       error('TSBehavior:infiniteLoop', ...
            %                             ['The concatenated stim trigger alignment ', ...
            %                             'failed, manual inspection necessary.\n'])
            %                    end
            %
            %                    % This *should* be the case given how we checked before,
            %                    % but things could get weird
            %                    for s = 1:size(swaps, 1)
            %                        idx = swaps(s, 1);
            %                        nextIdx = swaps(s, 2);
            %                        s2 = data.s2Events(idx);
            %                        s2Next = data.s2Events(nextIdx);
            %                        l = data.logEvents(idx);
            %                        lt = data.logEventTime(idx);
            %                        lNext = data.logEvents(nextIdx);
            %                        ltNext = data.logEventTime(nextIdx);
            %
            %                        % We could also have sequences that are small
            %                        % permutations since they occur so close in time.
            %                        % We'll consider these acceptable.
            %                        p = perms(data.logEvents(swaps(2,1)-2:swaps(2,2)+2));
            %
            %                        if (s2 == lNext) && (s2Next == l)
            %                            % Check if direct swap
            %                            data.logEvents(idx) = s2;
            %                            data.logEvents(nextIdx) = s2Next;
            %                            if lt ~= ltNext
            %                                data.logEventTime(idx) = ltNext;
            %                                data.logEventTime(nextIdx) = lt;
            %                            end
            %                            swaps(s, :) = [];
            %                            return
            %
            %                        elseif any(ismember(p, ...
            %                                data.s2Events(idx-2:nextIdx+2), ...
            %                                'rows'))
            %                            % Check if all the elements are there,
            %                            % but the lick times messed up tghe
            %                            % order a little bit. If so, we can
            %                            % eliminate the swap
            %                           swaps(s, :) = [];
            %                           return
            %                        else
            %                            error('EyeTracking:mismatchError', ...
            %                             'Spike2 and log file lick flags do not match.')
            %                        end
            %                    end
            %                end
            %
            %             end
            
            % If we've broken out of the loop, that means that all lick and
            % events flags match for the entire experiment, but not
            % necessarily the times. Let's see how well the two clocks match
            
            if inclEye
                % Check to see if frames or stims started first (usually it's
                % frames) and normalize to the one that started first. After
                % this step, the trigger times will be normalized in reference
                % to the frame acquisition start in terms of CPU time.
                frameTime0 = data.eyeData.timestamp(1);
                % Positive if stims started first
                frameStimDiff = frameTime0 - stimTime0;
                
                % Normalize log file time (PC time) to first
                % occurring time stamp
                if frameStimDiff > 0
                    % if stims started first
                    data.eyeData.timestamp = data.eyeData.timestamp ...
                        - stimTime0;
                    data.logOnTime = data.logOnTime - stimTime0;
                    data.lickTime = data.lickTime - stimTime0;
                    data.oriTime = data.oriTime - stimTime0;
                    data.logTime = data.logTime - stimTime0;
                    if ~isNew
                        logEvTimeCopy = logEvTimeCopy - stimTime0;
                    end
                else
                    % If the frames started first
                    data.eyeData.timestamp = data.eyeData.timestamp ...
                        - frameTime0;
                    data.logOnTime = data.logOnTime - frameTime0;
                    data.lickTime = data.lickTime - frameTime0;
                    data.oriTime = data.oriTime - frameTime0;
                    data.logTime = data.logTime - frameTime0;
                    if ~isNew
                        logEvTimeCopy = logEvTimeCopy - frameTime0;
                    end
                end
                
            else
                % No eye tracking data here
                data.logOnTime = data.logOnTime - stimTime0;
                data.lickTime = data.lickTime - stimTime0;
                data.oriTime = data.oriTime - stimTime0;
                data.logTime = data.logTime - stimTime0;
                if ~isNew
                    logEvTimeCopy = logEvTimeCopy - stimTime0;
                end
            end
            
            % Do an initial check for time alignment
            s2Starts = data.stimOn - data.stimOn(1);
            logStarts = data.logOnTime - data.logOnTime(1);
            meanTimeDiff = mean(s2Starts - logStarts);
            
            % Put the eye tracking fiming data on the Spike2 clock
            if inclEye
                if abs(meanTimeDiff) <= 1/data.frameRate
                    % we can consider this to be as good of an alignment
                    % as we're going to get without more intensive
                    % processing, so we'll take it
                    data.eyeData.timestamp = data.eyeData.timestamp ...
                        + meanTimeDiff;
                else
                    warning(['Trigger times misaligned by more than '...
                        '%0.1f ms (1 frame). Error is %0.0f ms. ', ...
                        'Realigning clocks...\n'], ...
                        (1/data.frameRate)*1000, ...
                        meanTimeDiff*1000)
                    
                    % Do an iterative clock alignment/time warp
                    data = TSBehavior.ClockCheck(data, data.stimOn, ...
                        data.logOnTime);
                    
                    % If we deviate from the eye tracking frame rate by
                    % more than 5% when
                    newFR = GetTrialDuration(data.eyeData.timestamp);
                    if newFR > 1/data.frameRate + 0.05/data.frameRate
                        warning(['Clock realignment changed eye ',...
                            'tracking frame rate to %0.1f FPS.\n'], ...
                            newFR)
                    else
                        disp('Eye tracking clock and Spike2 clock aligned.')
                    end
                end
            end
            
            %%%%%%%%THIS IS WHERE WE NEED TO ADDRESS ISSUE OF ONLY
            %%%BEING ABLE TO DO behavior stats OR calcium responses
            %%%%NEED both stimOn and logEvTimeCopy later on...
            if isNew
                data.events = data.stimID;
                data.eventTimes = data.stimOn;
            else
%                 Unlike the newer case, here the best bet we have for the
%                 stimulus flags is the log file, since now all
%                 conditions are sent to the DAQ.
                diffFromS2 = mean(data.stimOn-data.logOnTime);
                data.events = logEvCopy;
                data.eventTimes = logEvTimeCopy;
                %it's possible for the event times to be off. add s2 diff.
                data.eventTimes = data.eventTimes+diffFromS2
                %ori time is in log time, and needs to be adjusted
                data.oriTimes2p = data.oriTime+diffFromS2
            end
            
            % Reassign orientation times based on this newly realigned data.
            % We want to make sure we have the orientations for each stim.
            % Check to see that the orientations extracted from
            % ExtractBehaviorStates match those from the realigned events.
            oriIdxs = (data.events == 4 | data.events == 5);
            eventOris = data.events(oriIdxs);
            oriTime = data.eventTimes(oriIdxs);
            
            if ~isequal(eventOris, data.ori(1,:))
                error('TSBehavior:alignmentError', ['The time-realigned ', ...
                    'stimuli do not match those from the log file.\n'])
            else
                data.oriTime = oriTime;
            end
            
            % Housekeeping
            %             keys = {'logEvents', 'logEventTime', 's2Events', 's2EventTime'};
            keys = {'logEvents', 'logEventTime'};
            
            if ~isNew
                keys = [keys, {'userTrial', 'userTrialTime', 'airPuff', ...
                    'airPuffTime', 'hints', 'hintsTime', ...
                    'rewards', 'rewardsTime'}];
            end
            data = rmfield(data, keys);
            
        end
        
        function data = ClockCheck(data, s2Time, logTime)
            % CLOCKCHECK Helper function to align CPU and Spike2 times
            % between S2 stim codes and frame times.
            %
            %   Args:
            %       data: [struct] The data structure
            %
            %   Returns:
            %       data: [struct] updated data structure
            
            s2T = s2Time;
            lT = logTime;
            
            % This is a vector containing the mismatch between the two
            % clocks
            alignError = (s2T - s2T(1)) - (lT - lT(1));
            fIdxLast = 1;
            for i = 1:length(alignError)
                t = lT(i);
                % Find the closest eye tracking frame times to the data
                [~,fIdx,~] = FindNearest(data.eyeData.timestamp, ...
                    t);
                
                data.eyeData.timestamp(fIdxLast:fIdx) = ...
                    data.eyeData.timestamp(fIdxLast:fIdx)...
                    - alignError(i);
                fIdxLast = fIdx;
            end
        end
        
        function [block, lickAligned, stimAligned, lickStim] = ...
                FindBehaviorBlocks(states, stateTimes)
            % FINDBEHAVIORBLOCKS Finds trials during a behavior session
            %
            %   Args:
            %       states: [array] array of all state flags
            %       stateTimes: [array] array of all state times
            %   Returns:
            %       block: [array] indices of all blocks
            %       lickAlignedBlock: [array] indices of blocks aligned to
            %                         the initiation lick
            %       stimAlignedBlock: [array] indices of the blocks aligned
            %                         to stimulus onset
            
            % It looks like we sometimes drop an initialization. Let's
            % extract where all ones and zeros occur.
            droppedStart = [];
            blockIdx = find(states <= 1);
            
            % Okay, time for some stupid fancy stuff because we might have
            % dropped flags. This is going to be a recursive function which
            % looks for pairs in the list of blocks by zipping every other
            % element together. When we find a point of error, we make a
            % note of the index at which it occurs, remake the block list,
            % zip it again, etc. until all error sequences are found.
            blx = TSBehavior.RecursiveErrorSearch(states, stateTimes, ...
                blockIdx, droppedStart);
            
            % Now it's time to get a metric fuck ton of time points for
            % alignment. We have the basics for the start and end of trial
            % blocks where we can determine the outcome. Let's get those
            % first. Then we'll get points where we can align rasters to
            % the first lick following a trial ending, or where we align
            % the start of the first stimulus.
            block = zeros(length(blx), 4);
            lickAligned = zeros(length(blx), 5);
            stimAligned = zeros(length(blx), 4);
            lickStim = zeros(length(blx), 5);
            
            % seconds within which we will search for licks
            lickBuffer = 0.0;
            lickBufferB = 1;
            lickBufferF = 1;
            stimBuffer = 2.5;
            trialStates = [0, 1, 2 , 3, 4, 5, 6];
            
            for i = 1:length(blx)
                idx = blx(i,:);
                stims = states(idx(1):idx(end));
                % -- Gerneral trial indices -- %
                % The general trial start and end points are already found
                % in the blx variable
                
                % We need to identify when the stimulus actually starts
                % (i.e. code 4 or 5) and when the delay starts
                delayOn = idx(1) + find(stims == 2, 1) - 1;
                stimOn = find(stims == 4 | stims == 5, 1);
                if isempty(delayOn)
                    delayOn = idx(1)
                end
                if ~isempty(stimOn)
                    stimOn = idx(1) + stimOn - 1;
                else
                    stimOn = delayOn;
                end
                
                % General blocks with the delay as the alignment. If the
                % stim never started, use the end of the trial as an
                % approximation
                if stimOn == delayOn
                    block(i,:) = [idx(1), delayOn, idx(2), idx(2)];
                else
                    block(i,:) = [idx(1), delayOn, stimOn, idx(2)];
                end
                
                % -- Lick & Stim Aligned -- %
                % find the licks preceeding the delay screem
                trialLicks = find(states(idx(1):delayOn) == 31 | ...
                    states(idx(1):delayOn) == 30);
                
                % Select the last lick preceeding the delay screen and the
                % first lick following the init period
                if isempty(trialLicks)
                    firstLick = 1;
                    lastLick = 1;
                else
                    firstLick = trialLicks(1);
                    lastLick = trialLicks(end);
                end
                
                firstLickOn = idx(1) + firstLick - 1; % Account for 1 indexing
                firstLickOnT = stateTimes(firstLickOn);
                lastLickOn = idx(1) + lastLick - 1; % Account for 1 indexing
                lastLickOnT = stateTimes(lastLickOn);
                
                % The lick aligned periods consider the licking period
                % before the stimulus starts
                [~, lick0, ~] = FindNearest(stateTimes, ...
                    firstLickOnT - lickBufferB);
                lickAligned(i, :) = [lick0, firstLickOn, lastLickOn, ...
                    delayOn, stimOn];
                
                % The stim aligned blocks consider the period between trial
                % initiation (most recent lick) and the end of the trial
                stimAligned(i, :) = [lastLickOn, delayOn, stimOn, idx(end)];
                
                % Have long blocks that include all of this
                if stimOn == delayOn
                    lickStim(i, :) = [lick0, lastLickOn, delayOn, ...
                        idx(end), idx(end)];
                else
                    lickStim(i, :) = [lick0, lastLickOn, delayOn, ...
                        stimOn, idx(end)];
                end
            end
        end
        
        function blocks = RecursiveErrorSearch(stateChanges, stateTimes, ...
                blockIdx, droppedStart)
            % FINDBEHAVIORBLOCKS Finds trials during a behavior session
            %
            %   Args:
            %       states: [array] array of all state flags
            %       stateTimes: [array] array of all state times
            %   Returns:
            %       blocks: [array] corrected indices of all blocks
            
            block = stateChanges(blockIdx);
            
%             % The last init code can be ignored
%             if block(end) == 1
%                 blockIdx = blockIdx(1:end-1);
%                 block = block(1:end-1);
%             end
            
            starts = block(1:2:end);
            stops = block(2:2:end);
            tmpsz = min(length(starts),length(stops));
            blx = [starts(1:tmpsz); stops(1:tmpsz)];
            
            % We can check to see if there are mismatches in the pairing
            % initially before we enter the recursion state
            if all(blx(1,:) == 1) && all(blx(2,:) == 0)
                % We're good, return to the main funciton
                if length(blockIdx(1:2:end)')==length(blockIdx(2:2:end)')
                    blocks = horzcat(blockIdx(1:2:end)', blockIdx(2:2:end)');
                else if length(blockIdx(1:2:end)')==length(blockIdx(2:2:end)')+1
                        blocks = horzcat(blockIdx(1:2:end-1)', blockIdx(2:2:end)');
                    end
                end
                
            else
                for i = 1:length(blx)-1
                    % The structure of this simple. We find pairs of start/
                    % stop flags, and we can determine if we have an error
                    % by their values.
                    j = i*2 - 1 ;
                    k = j + 1;
                    
                    flag = blx(:, i);
                    % We have changed from correct blocks by either
                    % skipping a start or stop flag
                    if all(flag == [0; 1])
                        % Missing start flag
                        fprintf(['Missing a start flag before ', ...
                            '(normalized) time %0.0f.\n'], ...
                            stateTimes(j))
                        fprintf('Checking if this was a user-started trial\n')
                        
                        if ismember(22, stateChanges(blockIdx(j-1):blockIdx(j)))%joe changed from: ismember(22, stateChanges(blockIdx(j-1:j)))
                            fprintf(['This was a user-started trial. ', ...
                                'We ignore this anyways.\n'])
                            fprintf('The offending sequence shows %d \n', ...
                                stateChanges(blockIdx(j-1):blockIdx(j)+5))
                            %joe now dropping the dropped start blocks for
                            %self started trials
                            % Since these are indices, we don't have to do
                            % anything with the raw data, but this is still
                            % a pain. Record where these errors occur and
                            % what trial type they would be
                            droppedStart(end+1,:) = [blockIdx(j-1), blockIdx(j)];
                            blockIdx(j) = [];
                            
                            % Run recursion
                            blocks = TSBehavior.RecursiveErrorSearch(stateChanges, ...
                                stateTimes, ...
                                blockIdx, ...
                                droppedStart);
                        else
                            fprintf('This sequence is %d \n', flag)
                            fprintf('The offending sequence shows %d \n', ...
                                stateChanges(blockIdx(j-1):blockIdx(j)+5))
                            
                            % Since these are indices, we don't have to do
                            % anything with the raw data, but this is still
                            % a pain. Record where these errors occur and
                            % what trial type they would be
                            droppedStart(end+1,:) = [blockIdx(j-1), blockIdx(j)];
                            blockIdx(j) = [];
                            
                            % Run recursion
                            blocks = TSBehavior.RecursiveErrorSearch(stateChanges, ...
                                stateTimes, ...
                                blockIdx, ...
                                droppedStart);
                        end
                        
                    elseif all(flag == [0; 0])
                        % Missing start flag
                        fprintf(['Missing a start flag before ', ...
                            '(normalized) time %0.0f.\n'], ...
                            stateTimes(j))
                        fprintf('Checking if this was a user-started trial\n');
                        
                        if ismember(22, stateChanges(blockIdx(j:k)))
                            fprintf(['This was a user-started trial. ', ...
                                'We ignore this anyways.\n'])
                            fprintf('The offending sequence shows %d \n', ...
                                stateChanges(blockIdx(j-1):blockIdx(j)+5))
                            %joe now dropping the dropped start blocks for
                            %self started trials
                            % Since these are indices, we don't have to do
                            % anything with the raw data, but this is still
                            % a pain. Record where these errors occur and
                            % what trial type they would be
                            droppedStart(end+1,:) = [blockIdx(j-1), blockIdx(j)];
                            blockIdx(j) = [];
                            
                            % Run recursion
                            blocks = TSBehavior.RecursiveErrorSearch(stateChanges, ...
                                stateTimes, ...
                                blockIdx, ...
                                droppedStart);
                        else
                            fprintf('This sequence is %d \n', flag)
                            fprintf('The offending sequence shows %d \n', ...
                                stateChanges(blockIdx(j-1):blockIdx(k)+5))
                            
                            % Since these are indices, we don't have to do
                            % anything with the raw data, but this is still
                            % a pain. Record where these errors occur and
                            % what trial type they would be
                            droppedStart(end+1,:) = [blockIdx(k-1), blockIdx(k)];
                            blockIdx(j) = [];
                            
                            % Run recursion
                            blocks = TSBehavior.RecursiveErrorSearch(stateChanges, ...
                                stateTimes, ...
                                blockIdx, ...
                                droppedStart);
                        end
                        
                    elseif all(flag == [1; 1])
                        % Missing a stop flag
                        fprintf(['Missing a start flag before ', ...
                            '(normalized) time %0.0f.\n'], ...
                            stateTimes(k))
                        fprintf('This sequence is %d \n', flag)
                        fprintf('The offending sequence shows %d \n', ...
                            stateChanges(blockIdx(j-1):blockIdx(k)+5))
                        droppedStart(end+1,:) = [blockIdx(k-1), blockIdx(k)];
                        blockIdx(k) = [];
                        
                        % Run recursion
                        blocks = TSBehavior.RecursiveErrorSearch(stateChanges, ...
                            stateTimes, ...
                            blockIdx, ...
                            droppedStart);
                    else
                        % This is the [1; 0] sequence. This is correct, so
                        % do nothing.
                    end
                    if exist('blocks')==1
                        return
                    end
                end
            end
        end
        %%
        function [stimID, stimOn, logTrigger, logOnTime, numDrop, timeDrop] = RecursiveDropSearch(s2Trig, s2Time, ...
                logTrig, logTime, ...
                numDrop, timeDrop);
            
            
            %             %Recursively search for errors
            %             [data.stimID, data.stimOn, data.logTrigger, data.logOnTime, ...
            %                 numDrop, timeDrop] = TSBehavior.RecursiveDropSearch(...
            %                                         s2Trig, s2Time, ...
            %                                         logTrig, logTime, ...
            %                                         numDrop, timeDrop);
           
            
            
            if length(s2Trig)<length(logTrig(2,:))
                asdf1 =s2Trig;
                asdf2 = logTrig(2,:);
            else
                asdf2 =s2Trig;
                asdf1 = logTrig(2,:);
            end
            
            while length(find(asdf1~=asdf2(1:length(asdf1)))>0)
                asdf3 = [asdf1;asdf2(1:length(asdf1))];
                
                indDrop = find(asdf3(1,:)~=asdf3(2,:),1)
                
                timeDrop = [timeDrop indDrop];
                numDrop =numDrop+1;
                
                asdf2(indDrop) = [];
                if length(asdf1)==length(asdf2)
                    break
                end
            end
            
            if length(s2Trig)<length(logTrig(2,:))
                logTrig(:,timeDrop) = [];
                logTime(timeDrop) = [];
            else
                s2Trig(timeDrop) = [];
                s2Time(timeDrop) = [];
            end
            
            stimID = s2Trig;
            stimOn = s2Time;
            logTrigger = logTrig;
            logOnTime = logTime;

            
            
            
            
        end
        
        
        
        
        function frameIdx = AlignTrialFrames(time, ref, block)
            % ALIGNTRIALFRAMES Finds trials during a behavior session
            %
            %   Args:
            %       time: [array] timestamp of events
            %       ref: [array] reference time array to match to
            %       block: [array] indices of blocks defining an event
            %   Returns:
            %       frameIdx: [array] indices for the correct timepoints of
            %       the event block in terms of the reference time series.
            
            % The closest eye frame time to the time at which block states
            % change is found here. The index at which that frame time
            % occurs in the eye tracking data is returned
            frameIdx = NaN(size(block));
            
            for i = 1:length(block)
                b = block(i,:);
                if length(b) == 2
                    [~, t0, ~] = FindNearest(time, ref(b(1)));
                    [~, t1, ~] = FindNearest(time, ref(b(end)));
                    indexes = [t0, t1];
                elseif length(b) == 4
                    if b(1) == b(2) && b(1) ~= 1
                        [~, tBS, ~] = FindNearest(time, ...
                            ref(b(1)-1));
                        [~, t0, ~] = FindNearest(time, ...
                            ref(b(2)));
                        [~, t1, ~] = FindNearest(time, ...
                            ref(b(3)));
                        [~, tAS, ~] = FindNearest(time, ...
                            ref(b(4)));
                    else
                        [~, tBS, ~] = FindNearest(time, ...
                            ref(b(1)));
                        [~, t0, ~] = FindNearest(time, ...
                            ref(b(2)));
                        [~, t1, ~] = FindNearest(time, ...
                            ref(b(3)));
                        [~, tAS, ~] = FindNearest(time, ...
                            ref(b(4)));
                    end
                    indexes = [tBS, t0, t1, tAS];
                elseif length(b) == 5
                    if b(1) == b(2) && b(1) ~= 1
                        [~, tBS, ~] = FindNearest(time, ...
                            ref(b(1)-1));
                        [~, t0, ~] = FindNearest(time, ...
                            ref(b(2)));
                        [~, t1, ~] = FindNearest(time, ...
                            ref(b(3)));
                        [~, t2, ~] = FindNearest(time, ...
                            ref(b(4)));
                        [~, tAS, ~] = FindNearest(time, ...
                            ref(b(5)));
                    else
                        [~, tBS, ~] = FindNearest(time, ...
                            ref(b(1)));
                        [~, t0, ~] = FindNearest(time, ...
                            ref(b(2)));
                        [~, t1, ~] = FindNearest(time, ...
                            ref(b(3)));
                        [~, t2, ~] = FindNearest(time, ...
                            ref(b(4)));
                        [~, tAS, ~] = FindNearest(time, ...
                            ref(b(5)));
                    end
                    indexes = [tBS, t0, t1, t2, tAS];
                end
                frameIdx(i,:) = indexes;
            end
        end
        
        function data = FindTrialType(data, block, lickBlock, stimBlock, ...
                lickStimBlock, inclEye, rejectUser)
            % FINDTRIALTYPE Uses the event flags to determine trial outcome
            %
            %   Args:
            %       data: [struct] all experiment data
            %       block: [array] indices of blocks defining an event
            %       lickBlock: [array] indices of blocks with reference to
            %       the iitiating lick
            %       stimBlock: [array] indices of block with reference to
            %       the start of the delay period
            %   Returns:
            %       data: [struct] all experiment data, updated to include
            %       the block outcome, stimulus orientations for each trial,
            %       the indices for all blocks in reference to the eye
            %       tracking clock, and the indices for all clocks in
            %       reference to the two photon times
            
            % Get the indices of behavior blocks in terms of eye tracking
            % times
            if inclEye
                data.blocksET = TSBehavior.AlignTrialFrames(data.eyeData.timestamp, ...
                    data.eventTimes, block);
                data.lickBlockET = TSBehavior.AlignTrialFrames(data.eyeData.timestamp, ...
                    data.eventTimes, lickBlock);
                data.stimBlockET = TSBehavior.AlignTrialFrames(data.eyeData.timestamp, ...
                    data.eventTimes, stimBlock);
                data.LSBlockET = TSBehavior.AlignTrialFrames(data.eyeData.timestamp, ...
                    data.eventTimes, lickStimBlock);
            end
            
            % Do the same but for 2P times
            data.blocks2P = TSBehavior.AlignTrialFrames(data.twophotontimes, ...
                data.eventTimes, block);
            data.lickBlock2P = TSBehavior.AlignTrialFrames(data.twophotontimes, ...
                data.eventTimes, lickBlock);
            data.stimBlock2P = TSBehavior.AlignTrialFrames(data.twophotontimes, ...
                data.eventTimes, stimBlock);
            data.LSBlock2P = TSBehavior.AlignTrialFrames(data.twophotontimes, ...
                data.eventTimes, lickStimBlock);
            
            % Reward periods
            timeoutKey = 0;
            initKey = 1;
            delayKey = 2;
            grayKey = 3;
            sPlusKey = 4;
            sMinusKey = 5;
            rewardKey = 6;
            % User intervention
            userRewardKey = 20;
            userPuffKey = 21;
            user_startKey = 22;
            % outcomes (correct/wrong/hinted)
            airPuffKey = 21; %normally 40
            hinted = 41;
            correct = 50;
            
            % counts for quick eval
            num_h = 0;
            num_m = 0;
            num_cr = 0;
            num_fa = 0;
            num_nr = 0;
            num_te1 = 0;
            num_te2 = 0;
            num_te3 = 0;
            num_j = 0;
            num_ur = 0;
            num_us = 0;
            
            pad = 0;
            allKinds = {};
            ori = {};
            oTime = {};
            
            % Note: The key for each stim code is:
            % 0: junk, 1: hit, 2: miss, 3: FA, 4: CR,
            % 5: NR, 6: TE1, 7: TE2, 8: TE3
            
            for i = 1:length(block)
                idxs = block(i, :);
                idx = idxs(1);
                trial = data.events(idxs(1):idxs(end)+pad);
                trialTimes = data.eventTimes(idxs(1):idxs(end)+pad);
                trlLicks = [trial~=30 & trial ~=31];
                % remove licks
                trial = trial(trlLicks);
                trialTimes = trialTimes(trlLicks);
                
                if trial(1) ~= 1
                    trial = trial(1:end);
                end
                
                % This is a stupid way to make sure we don't have
                % overlapping trials. For example, say the trial events are
                % [1, 3, 5, 4, 6, 0, 1]. Here the last index is the init key
                % from the next trial. What we do is reverse the order of
                % the trial [1, 0, 6, 4, 5, 3, 1], check to see if there is
                % is an init key in the flipped array somewhere from the
                % first element to the timeout key. If this is true, we
                % then remove the offnding elements from the flipped array,
                % then flip the array back.
                
                test = fliplr(trial);
                if trial(1) ~= timeoutKey && ...
                        ismember(initKey, test(1:find(test==timeoutKey)))
                    test = test(find(test==initKey)+1:end);
                    trial = fliplr(test);
                end
                
                if ismember(userRewardKey, trial)
                    % We don't like trials where we give free reward
                    allKinds(end+1,:) = {0, idxs};
                    num_ur = num_ur + 1;
                    ori(end+1,:) = {nan,nan};
                    
                elseif ismember(user_startKey, trial) && rejectUser
                    % We also dont like trials that we had to start
                    allKinds(end+1,:) = {0, idxs};
                    num_us = num_us + 1;
                    ori(end+1,:) = {nan,nan};
                    
                elseif all(ismember([initKey, delayKey, timeoutKey], trial)) ...
                        && ~any(ismember([sMinusKey, sPlusKey], trial))
                    % Trial timeout before stim presented
                    allKinds(end+1,:) = {0, idxs};
                    num_j = num_j + 1;
                    ori(end+1,:) = {nan,nan};
                    
                    % All trials with an S-
                elseif ismember(sMinusKey, trial)
                    % find the orientation and spatial freq. of the stim
                    s_min = find(trial == sMinusKey) + idx - 1;
                    idxs(end+1) = s_min;
                    %joe making a change here to get stim time and ori
                    %9/27/20
                    stOn = find(data.oriTime==trialTimes(find(trial == sMinusKey)));
                    ori(end+1,:) = {data.ori(2,stOn),data.oriTime(stOn)};
                    
                    
                    
                    
                    if ismember(airPuffKey, trial)
                        % animal licked after the s Minus
                        allKinds(end+1,:) = {3, idxs};
                        num_fa = num_fa + 1;
                        
                    elseif ismember(correct, trial)
                        % Animal got the reject and bonus correct
                        idxs(end+1) = find(trial == sPlusKey) + idx;
                        allKinds(end+1,:) = {4, idxs};
                        num_cr = num_cr + 1;
                        
                    elseif ~ismember(airPuffKey, trial) && ~ismember(correct, trial)
                        if ismember(rewardKey, trial)
                            % animal correctly ignored S-, but did not lick
                            % for the S+
                            idxs(end+1) = find(trial == sPlusKey) + idx;
                            allKinds(end+1,:) = {5, idxs};
                            num_nr = num_nr + 1;
                            
                        elseif ismember(sPlusKey, trial) && ~ismember(rewardKey, trial)
                            % animal correctly ignored the S-, but licked
                            % during the S+
                            idxs(end+1) = find(trial == sPlusKey) + idx;
                            allKinds(end+1,:) = {6, idxs};
                            num_te1 = num_te1 + 1;
                            
                        else
                            % Animal licked after the S-
                            if data.airPuffMode == 0
                                allKinds(end+1,:) = {3, idxs};
                                num_fa = num_fa + 1;
                            else
                                allKinds(end+1,:) = {7, idxs};
                                num_te2 = num_te2 + 1;
                            end
                        end
                    end
                    
                    % All trials with only an S+
                elseif ismember(sPlusKey, trial) && ~ismember(sMinusKey, trial)
                    s_plus = find(trial == sPlusKey) + idx - 1;
                    idxs(end+1) = s_plus;
                    %joe making a change here to get stim time and ori
                    %9/27/20
                    stOn = find(data.oriTime==trialTimes(find(trial == sPlusKey)));
                    ori(end+1,:) = {data.ori(2,stOn),data.oriTime(stOn)};
                    
                    if ismember(correct, trial)
                        % animal correctly identifies an S+
                        allKinds(end+1,:) = {1, idxs};
                        num_h = num_h + 1;
                    else
                        if ismember(rewardKey, trial)
                            % animal ignores the S+
                            allKinds(end+1,:) = {2, idxs};
                            num_m = num_m + 1;
                        else
                            % animal ignores the S+
                            allKinds(end+1,:) = {8, idxs};
                            num_te3 = num_te3 + 1;
                        end
                    end
                    
                else
                    % something else happened
                    allKinds(end+1,:) = {0, idxs};
                    num_j = num_j + 1;
                    ori(end+1,:) = {nan,nan};
                end
            end
            
            fprintf(['Hits: %d\nMisses: %d\nCorrect Reject: ', ...
                '%d\nFalse Alarm: %d\nNR: %d\nTE1: %d\nTE2: ', ...
                '%d\nTE3: %d\n'], num_h, num_m, num_cr, num_fa, ...
                num_nr, num_te1, num_te2, num_te3)
            fprintf('%d trials rejected due to user giving rewards.\n', ...
                num_ur)
            fprintf('%d trials rejected due to user starting trials.\n', ...
                num_us)
            fprintf('%d of %d trials rejected.\n', num_ur+num_us, ...
                length(block))
            
            data.blockOutcome = cell2mat(allKinds(:, 1));
            
            data.stimOrientations = TSBehavior.ExtractStimOri(data, ...
                data.eventTimes, allKinds);
            data.stimOrientations2 = [cell2mat(ori(:,1)) cell2mat(ori(:,2)) cell2mat(allKinds(:, 1))];
        end
        
        function stimKind = ExtractStimOri(data, eventTimes, block)
            % EXTRACTSTIMORI Finds the time and orientation of each S+ or
            % S-
            %   Args:
            %       data: [struct] all experiment data
            %       eventTimes: [array] indices of blocks defining an event
            %       block: [array] indices of blocks defining an event
            %
            %   Returns:
            %       stimKind: [array]contains either the orientation, time,
            %       and block sequence (including outcome) of a trial, or
            %       just the time orientation and time.
            
            % The closest frame time to the time at which block states
            % change is found here. The frame time is returned
            if isempty(block)
                return
            end
            
            stimKind = {};
            blockCopy = block;
            
            if isfloat(blockCopy{1, 1})
                block = block(:, end);
                
                for j = 1:length(block)
                    i = cell2mat(block(j));
                    
                    if length(i) <= 3
                        % do nothing
                    elseif length(i) == 4
                        [~, idx, ~] = FindNearest(data.oriTime, ...
                            eventTimes(i(end)));
                        stim1 = data.ori(:,idx);
                        [~, ~, time1] = FindNearest(data.eventTimes, ...
                            data.oriTime(idx));
                        stimKind(end+1,:) = [j, stim1, time1, blockCopy(j,1)];
                        
                    elseif length(i) == 5
                        [~, idx1, ~] = FindNearest(data.oriTime, ...
                            eventTimes(i(end-1)));
                        [~, idx2, ~] = FindNearest(data.oriTime, ...
                            eventTimes(i(end)));
                        
                        if idx1 == idx2 && idx1 ~= length(data.ori)
                            idx2 = idx2 + 1;
                        elseif idx1 == idx2 && idx1 == length(data.ori)
                            idx1 = idx1 - 1;
                        end
                        
                        stim1 = data.ori(:,idx1);
                        stim2 = data.ori(:,idx2);
                        [~, ~, time1] = FindNearest(data.eventTimes, ...
                            data.oriTime(idx1));
                        [~, ~, time2] = FindNearest(data.eventTimes, ...
                            data.oriTime(idx2));
                        stimKind(end+1,:) = [j, stim1, time1, blockCopy(j,1)];
                        stimKind(end+1,:) = [j, stim2, time2, blockCopy(j,1)];
                    end
                end
                
            else
                for j = 1:length(block)
                    i = block(j);
                    
                    if length(i) <= 3
                        % pass
                    elseif length(i) == 4
                        [~, idx, ~] = FindNearest(data.oriTime, ...
                            eventTimes(i(end)));
                        stim1 = data.ori(:,idx);
                        time1 = data.oriTime(idx);
                        stimKind(end+1,:) = [j, stim1, time1];
                        
                    elseif length(i) == 5
                        [~, idx1, ~] = FindNearest(data.oriTime, ...
                            eventTimes(i(end-1)));
                        [~, idx2, ~] = FindNearest(data.oriTime, ...
                            eventTimes(i(end)));
                        if idx1 == idx2
                            idx2 = idx2 + 1;
                        end
                        
                        stim1 = data.ori(:,idx1);
                        stim2 = data.ori(:,idx2);
                        time1 = data.oriTime(idx1);
                        time2 = data.oriTime(idx2);
                        stimKind(end+1,:) = [j, stim1, time1];
                        stimKind(end+1,:) = [j, stim2, time2];
                    end
                end
            end
        end
        
        function data = StimByOrientation(data, timeConst)
            % STIMBYORIENTATION Finds the time and orientation of each S+ or
            % S-
            %   Args:
            %       data: [struct] all experiment data
            %
            %   Returns:
            %       data: [struct] updated data structure with the
            %       substructure validStimBlocks, which contains only the
            %       trials where the animal successfully rejected or
            %       identified and S- or S+
            
            
            % This function pulls all of the S+ and S- occurrences and
            % presents them with their Spike2 time stamp and orientation
            
            % Get all isntances of flags in both cases
            whereStim = find(data.events == 4 | data.events == 5);
            stims = data.events(whereStim);
            stimTimes = data.eventTimes(whereStim);
            
            % Do the same thing for the orientation data we pulled earlier
            stim = data.ori(1,:);
            theta = data.ori(2,:);
            
            uniqueOri = unique(theta);
            data.numOris = zeros(length(uniqueOri),2);
            
            for i = 1:length(uniqueOri)
                count = sum(theta == uniqueOri(i));
                data.numOris(i,:) = [uniqueOri(i), count];
            end
            
            % orientation times are in reference to PC time. Need to see
            % how well they line up to the log time
            if isequal(stimTimes, data.oriTime)
                % The times are already equal, just need to grab the
                % Spike2 times
                fprintf('Orientation times are aligned.\n')
            else
                % Check how bad this mismatch is
                vv = find(data.oriTime ~= stimTimes, 1);
                if abs(data.oriTime(vv) - stimTimes(vv)) <= 1/data.frameRate
                    % This is fine, just pass
                elseif abs(data.oriTime(vv) - stimTimes(vv)) <= timeConst/data.frameRate
                    % We are off by timeConst frames. Not ideal, but still
                    % acceptable, so warn the user but don't break
                    warning(['Trigger times and orientation data time', ...
                        'points are misaligned by more than one camera frame.']);
                else
                    % We have a problem
                    error('EyeTracking:alignmentError', ...
                        ['Trigger times and orientation data time ', ...
                        'points are misaligned!']);
                end
            end
            
            % Compare to the extra data we extracted earlier. These are
            % only the trials where we kept the data (good blocks) so there
            % may be fewer than the stuff pulled from the main data set.
            matches = zeros(length(data.stimOrientations), 5);
            for i = 1:length(data.stimOrientations)
                t = data.stimOrientations(i,:);
                matchT = FindNearest(data.oriTime, t{3});
                matches(i, :) = [t{1}, t{end}, t{2}(1), t{2}(2), matchT];
            end
            
            fprintf('Total number of stims: %d.\n', length(stims));
            fprintf('Number of stims in valid blocks: %d.\n', ...
                length(matches));
            
            % make substructures in the data object that hold data from the
            % stims in valid blocks vs the stims in all blocks
            fields = {'blockIdx', 'outcome', 'stim_type', 'orientation', 'time'};
            data.validStimBlocks = struct();
            for i = 1:length(fields)
                data.validStimBlocks.(fields{i}) = matches(:,i);
            end
        end
        
        
    end
    
end

%% Helper Functions
function [minDistance, indexOfMin, minVal] = FindNearest(array, value)
% FINDNEAREST Finds the nearest neighbor to the input value in
% an array
%
%   Args:
%       array: [array] A row or column vector
%       value: [float, int] The value to find in the array
%
%   Returns:
%       minDistance: [float] the difference between the input
%       value and its nearest neighbor
%       indexOfMin: [int] index in the array of the nearest
%       neighbor
%       minVal: [float] the value of the nearest neighbor

[minDistance, indexOfMin] = min(abs(array - value));
minVal = array(indexOfMin);
end

function diff = GetTrialDuration(data)
% GETTRIALDURATION Finds the mean pairwise difference between
%  all elements in an array
%
%   Args:
%       data: [array] A row or column vector
%
%   Returns:
%       diff: [float] mean difference between each pair of
%       elements in the array

diff = mean(data(2:2:end) - data(1:2:end-1));
end
