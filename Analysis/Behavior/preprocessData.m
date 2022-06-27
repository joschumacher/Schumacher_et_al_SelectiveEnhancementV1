% preprocessEyeData.m
% Max Planck Florida Institute for Neuroscience
% Author: Matthew McCann (@mkm4884)
% Created: 29 March 2018
% Last Modified:

% Description: A script to preprocess the eye tracking data and align the
% CPU clocked frames with the Spike2 clocked stim codes and two photon
% frame times.

%% Init
clear; clc;

% Find the user so that we can set the base directories only once and share
% this around with other people in the lab
os = computer;
switch os
    case 'PCWIN64'
        user = getenv('username');
    otherwise
        user = getenv('USER');
end

% Set path to where your data lives. Only needs to be done once. Can add
% new users or modify data directories as needed.
basedirs = struct('mccannm', 'F:/Data_Temp', ...
    'schumacherj', 'C:\Data\Animal',...
                  'RodriguezG', 'Z:\Gabriela\scripts from joe\ExampleGCampAnalysis\');
              
              % 'Z:/Joe/Data', ...
              %'SchumacherJ','G:/Animal',...

%% Animal & Directory Setup
% folders = struct('vida', [109 110] ...
%                  );
             
% folders = struct('vida', [72] ...
%                  );

folders = struct('vida', [112] ...
                 );
             
% folders = struct('qbert', [53] ...
%                );

folders = struct('shrewby', [20] ...
               );
           
folders = struct('amidala', [77] ...
               );
           
folders = struct('splinter', [44] ...
               );
           
folders = struct('baby', [12] ...
               );
           
folders = struct('amidala', [82] ...
               );
           
folders = struct('splinter', [37] ...
               );
           
% folders = struct('Vida', [55] ...
%                );

folders = struct('qbert', [35] ...
               );
           
folders = struct('Clucker', [14] ...
               );    

folders = struct('chewie', [62] ...
               );   
folders = struct('baby', [31] ...
               );
           
folders = struct('fresa', [16] ...
               );

%            folders = struct('splinter', [31] ...
%                );
           
           folders = struct('qbert', [53] ...
               );
           folders = struct('fresa', [66] ...
               );
% folders = struct('splinter', [9] ...
%                );

%% Big Try-Catch Loop for Errors and Such
skipped = [];
f = fields(folders);

for i = 1:length(f)
    animal = f{i};
    
    for j = 1:length(folders.(animal))
        exptNum = folders.(animal)(j);
        
        % Try to process the trial, and abandon if an error occurs
        %try
            fprintf('#################################\n')
            fprintf('Processing data from %s %d...\n', animal, exptNum)

            % General data directory
            basedir = fullfile(basedirs.(user));

            % Get data - heavy lifting is done in the EyeTracking class
            exptData = TSBehavior.LoadData(animal, exptNum, basedir, ...
                                           'timelockconstraint', 4);

            % If we're using offline eye tracking data, scrap all the 
            % online data except the frame times, replace it  with offline 
            % data, then delete the now unnecessary online data
            if exptData.metadata.useOffline
                exptData = TSBehavior.ReplaceOnlineOfflineTimes(exptData);
            end

            %% Look Up Stim Codes -----------------------------------------
            % look up the spike2 stim codes in terms of degrees
            stimLookup = TSBehavior.LookupStimCodes(exptData.data.stimID, ...
                                             exptData.metadata.isBehavior, ...
                                             animal, ...
                                             exptData.metadata.isSpike2New);

            % The key 'stimID' in the structure is actually just the index 
            % for the angles stored in stimLookup for the current animal. 
            % Replace them here.
            if ~exptData.metadata.isBehavior
                exptData.data.stimOris = zeros(size(exptData.data.stimID));

                for s = 1:length(exptData.data.stimID)
                    exptData.data.stimOris(s) = stimLookup(exptData.data.stimID(s));
                end

            else
                % For behavioral data, we'll keep the "stimID" as stim 
                % codes, but we'll store a human readable version under the 
                % key 'sCodes'
                exptData.data.sCodes = cell(size(exptData.data.stimID));
                
                % This is a stupid hack that compensates for bad
                % decisions made when running Vida
                if strcmp(animal, 'vida') && any(ismember(exptData.data.stimID, ...
                                                      36))
                    exptData.data.stimID(exptData.data.stimID == 30) = 20;
                    exptData.data.stimID(exptData.data.stimID == 31) = 21;
                    exptData.data.stimID(exptData.data.stimID == 36) = 6;
                end
                
                % Ensure some backwards compatability
                if any(ismember(exptData.data.stimID, 42))
                    exptData.data.stimID(exptData.data.stimID == 42) = 50;
                    exptData.data.stimID(exptData.data.stimID == 40) = 21;
                end
                
                for s = 1:length(exptData.data.stimID)
                    code = exptData.data.stimID(s);
                            
                    if code <= 6
                        tag = stimLookup{code+1};
                    elseif code <= 15 && code >= 10
                        tag = stimLookup{code - 1};
                    elseif 20 <= code && code < 30
                        tag = stimLookup{code - 6};%was code -5, trying for old animals
                    elseif 30 <= code && code < 40
                        tag = stimLookup{code - 12};
                    elseif code >= 40 && code < 50
                        tag = stimLookup{code - 21}; 
                    elseif code == 50;
                        tag = stimLookup{code - 29};
                    elseif code == 80;
                        tag = stimLookup{code - 60};
                    end

                    exptData.data.sCodes{s} = tag;
                end
            end

            % housekeeping
            clear stimLookup;

            %% Align Time Stamps from CPU and Spike2 ----------------------
            % Now the real fun begins. Let's start aligning times.
            if exptData.metadata.isBehavior
               exptData.data = TSBehavior.ExtractBehaviorStates(exptData.data, ...
                                            exptData.metadata.isSpike2New);

               exptData.data = TSBehavior.CorrectStimErrors(exptData.data, ...
                                                            exptData.metadata);

               exptData.data = TSBehavior.AlignBehaviorTimes(exptData.data, ... 
                                     exptData.metadata.isEyeTracking, ...
                                     exptData.metadata.isSpike2New, ...
                                     exptData.metadata.timeLockConstraint);

               [behaviorBlocks, lickAlignedBlocks, stimAlignedBlocks, lickStimBlocks] = ...
                        TSBehavior.FindBehaviorBlocks(exptData.data.events, ...
                                                 exptData.data.eventTimes);

               exptData.data = TSBehavior.FindTrialType(exptData.data, ...
                                                        behaviorBlocks, ...
                                                        lickAlignedBlocks, ...
                                                        stimAlignedBlocks, ...
                                                        lickStimBlocks, ...
                                                        exptData.metadata.isEyeTracking, ...
                                                        exptData.metadata.rejectUser);

               exptData.data = TSBehavior.StimByOrientation(exptData.data, ...
                                     exptData.metadata.timeLockConstraint);

            else
               exptData.data = TSBehavior.AlignPassiveTimes(exptData.data, ...
                                          exptData.metadata.isEyeTracking);
               exptData.data = TSBehavior.GetPassiveBlocks(exptData.data, ...
                                          exptData.metadata.isEyeTracking);
            end

            %% Save Data
            save(exptData.metadata.savePath, 'exptData', '-v7.3');
            fprintf('Experiment %s %d successfuly processed!\n\n', ...
                    animal, exptNum)
                        
%         % This part handles the errors that might occur when processing
%         catch e %e is an MException struct
%             % Add the error to the list of skipped experiments
%             skipped(end+1) = exptNum;
%             
%             % Process errors
%             fprintf(1,'There was an error! The identifier was:\n%s\n', ...
%                     e.identifier);
%             fprintf(1,' The message was:\n%s\n',e.message);
%             fprintf(1,' The error occured at line %d\n',e.stack(1).line);
% 
%             
%             % more exception handling
%             switch e.identifier
%                 case 'EyeTracking:alignmentError'
%                     fprintf(['An alignment error occurred. Manual ', ...
%                              'inspection is needed to determine the ', ...
%                              'cause of the error.\n'])
%                          
%             case 'EyeTracking:mismatchError'
%                     fprintf(['An mismatch error occurred. Manual ', ...
%                              'inspection is needed to locate any major or ', ...
%                              'obvious flag mismatches.\n'])                         
%                          
%                 case 'EyeTracking:recursionError'
%                     fprintf(['An infinite recursion error occurred. ', ...
%                              'Manual inspection is needed to determine ', ...
%                              'the cause of the error.\n'])
%                          
%                 case 'EyeTracking:lickFileError'
%                     fprintf(['A lick file error occurred. Make sure ', ...
%                             'you rerun the Spike2 data to produce ', ...
%                             'licktimes.txt. If you want to use the ', ...
%                             'log file for lick timing, set which_lick ', ...
%                             'to ''log''.\n'])
%                     
%                     if strcmp(user, 'schumacherj')
%                         fprintf('Yes, Joe, you do need to reurn some data...')
%                     end
%             end   
        %end
        
    end
    
    % Give the user an output for the experiments that were skipped for
    % each animal
    if ~isempty(skipped)
        warning('Skipped these experiments in %s''s directory:\n%s', ...
                animal, sprintf('%d ', skipped))
        skipped = [];
    end
    
end