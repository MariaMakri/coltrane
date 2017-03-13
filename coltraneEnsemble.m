function [cases,pot,pop,p1,forcing1] = ...
	coltraneEnsemble(forcingCase,forcingOptions,paramOptions,fileBasename);

% [cases,pot,pop,p1,forcing1] = ...
%     coltraneEnsemble(forcingCase,forcingOptions,paramOptions,fileBasename);
%
% framework for running families of cases of coltraneModel.m, varying the
% environmental forcing, biological parameters, or both.
%
% e.g.
% ... coltraneEnsemble('simple',...
%                     {'dtPmax',[90 180],'T0mean',4},...
%                     {'m0',0.01,'Nyears',3,'u0',[0.006 0.008 0.01]}),...
%					  'myfile');
% runs 2x3 cases and save the results to myfile1.mat ... myfile6.mat. If 
% fileBasename is omitted or empty, returns summary stats only.
%
% as in the output from a single coltraneModel.m case, _pot_ is stats from the
% potential (phi) model, and _pop_ is stats from the egg/reserve (ER) model.
% only scalar stats are retained.


if nargin<4, fileBasename = ''; end

NF = length(forcingOptions)/2;
NP = length(paramOptions)/2;

% generate all combos of params
outputList = '[';
for i=1:NF
	N(i) = length(forcingOptions{i*2});
	outputList = [outputList 'cases.' forcingOptions{i*2-1} ','];
end
for i=1:NP
	N(NF+i) = length(paramOptions{i*2});
	outputList = [outputList 'cases.' paramOptions{i*2-1} ','];
end
outputList(end) = ']';
eval([outputList ' = ndgrid(forcingOptions{2:2:end},paramOptions{2:2:end});']);

N1 = [N(N>1) 1 1]; % with singleton dimensions removed
Ntot = prod(N);
disp([num2str(Ntot) ' cases']);

% run the first case to get sample output, and set aside the p, forcing 
% structures
out1 = runOneCase(1,cases,forcingCase,forcingOptions,paramOptions);
p1 = out1.p;
forcing1 = out1.forcing;
[~,potFields] = scalarStats(out1.pot);
[~,popFields] = scalarStats(out1.pop);

% main loop ---------------------------------
parfor_progress(Ntot);
parfor k=1:Ntot
	outk = runOneCase(k,cases,forcingCase,forcingOptions,paramOptions);
	% save the results
	if ~isempty(fileBasename)
		saveOneCase(k,fileBasename,outk);
	end	
	pot_k = scalarStats(outk.pot);
	pop_k = scalarStats(outk.pop);
	potMatrix(k,:) = pot_k;	
	popMatrix(k,:) = pop_k;	
	parfor_progress;
end
parfor_progress(0);

% clean up output structures ----------------
for i=1:length(potFields)
	pot.(potFields{i}) = reshape(potMatrix(:,i),N1);
end
for i=1:length(popFields)
	pop.(popFields{i}) = reshape(popMatrix(:,i),N1);
end
fields = fieldnames(cases);
for i=1:length(fields)
	u = unique(cases.(fields{i})(:));
	if length(u) > 1
		cases.(fields{i}) = reshape(cases.(fields{i}),N1);
	else
		cases = rmfield(cases,fields{i});
	end
end




% ------------------------------------------------------------------------------


function out = runOneCase(k,cases,forcingCase,forcingOptions,paramOptions);
NF = length(forcingOptions)/2;
NP = length(paramOptions)/2;
% run one case
opt = forcingOptions;
for i=1:NF
	opt{i*2} = cases.(forcingOptions{i*2-1})(k);
end
forcing0 = coltraneForcing(forcingCase,opt{:});
opt = paramOptions;
for i=1:NP
	opt{i*2} = cases.(paramOptions{i*2-1})(k);
end
p = coltraneParams(opt{:});
out = coltraneModel(forcing0,p);


function saveOneCase(k,fileBasename,v,p,forcing);
fname = num2filename(fileBasename,k);
try
	save([fileBasename fnum],'v');
catch
	fslash = strfind(fname,'/');
	thedir = fname(1:fslash(end));
	if ~exist(thedir,'dir')
%		disp([thedir ' not found, creating']);
		mkdir(thedir);
	end
	save(fname,'v');
end
if nargin>=5
	save(fname,'-append','forcing');
end
if nargin>=4
	save(fname,'-append','p');
end


function [stats,names] = scalarStats(v);
% returns a vector containing all SCALAR fields of v, along with their names
allFields = fieldnames(v);
for i=1:length(allFields)
	keep(i) = prod(size(v.(allFields{i})))==1 & isnumeric(v.(allFields{i}));
end
names = allFields(keep);
for i=1:length(names)
	stats(i) = v.(names{i});
end
