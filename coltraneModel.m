function [v,fl] = coltraneModel(forcing,p,whatToSave);

% v = coltraneModel(forcing, p, 'fitness only' | 'scalars only' | 'everything');
%
% "dia18" (DIAPOD, 2018) version of the Coltrane model. This has diverged 
% significantly from the Coltrane 1.0 model used in Banas et al. 2016: it's 
% closest to the "separable" branch on github.
%
% forcing is a structure specifying a single time series of forcing and 
% 		ancillary variables. Cohorts are generated by varying spawning date
% 		across the first year.
% p is a structure containing the internal model parameters. These should
%		all be scalars.
%
% relationship with the published Coltrane model (Front. Mar. Res. 2016):
% * the phi model is hereby abandoned
% * R,S are collapsed into a single state variable W = S + R. Allometric
%		formulas using S in the paper now use W.
% * This is actually an approximate solution which doesn't require iteration 
%		across all state variables in time. This makes the model cleanly 
% 		hierarchical, so that one can derive predictions about
%				development alone (D),
% 				then size and time evolution in surviving cohorts (D,W),
% 				then mortality, survivorship, and population dynamics (D,W,N).
%		This will also make it possible for N to be density-dependent in a 
%		future version.
% * The myopic criterion for diapause has been replaced by a matrix of entry
%		and exit dates, which are considered in a brute-force way parallel
% 		to spawning date.
% * tegg has been replaced by dtegg, which is similar to (tegg - t0):
%
%	NT			NC			NDx			NDn			NE
%	t			t0			tdia_exit	tdia_enter	dtegg
%	timestep	spawn date	exit date	entry date	egg prod date
%	(calendar)	(calendar)	(yearday)	(yearday)	(relative to t0)
%
% the last three dimensions are folded into a single strategy vector s.
%
%
% the last argument works like this:
% 'fitness only': the model calculates the full fitness landscape and stops,
% 		returning [] for v and something useful for fl.
% 'everything': after calculating fl, the model re-runs the fit cases and
%		saves full time series
% 'scalars only': as for 'everything', but only metrics that aren't time series
% 		are returned. This option would make more sense if there were also
%		options for the strictness of the filtering criterion.


if nargin < 3, whatToSave = 'everything'; end


% calculate yearday, if it wasn't supplied
if ~isfield(forcing,'yday')
	forcing.yday = reshape(yearday(forcing.t),size(forcing.t));
end
NT = size(forcing.t,1); % # timesteps


% vectors of timing parameters t0, tdia_exit, tdia_enter, dtegg
t0 = forcing.t(1) : p.dt_spawn : (forcing.t(end) - 365);
	% the spawning dates to consider
NC = length(t0);
tdia_exit = p.tdia_exit;
if isempty(tdia_exit)
	tdia_exit = 0 : p.dt_dia : 365/2; % diapause exit yeardays
end
NDx = length(tdia_exit);
tdia_enter = p.tdia_enter;
if isempty(tdia_enter)
	tdia_enter = (max(tdia_exit) + p.dt_dia) : p.dt_dia : 365; % entry dates
end
NDn = length(tdia_enter);
dtegg = p.dtegg;
if isempty(dtegg)
	dteggmin = (p.min_genlength_years - 0.5) .* 365;
	dteggmin = max(dteggmin, p.dt_spawn);
	dteggmax = (p.max_genlength_years + 0.5) .* 365;
	dteggmax = min(dteggmax, forcing.t(end) - t0(end));
	dtegg = dteggmin : p.dt_spawn : dteggmax;
		% the date that egg production begins relative to t0
end
NE = length(dtegg);


% construct the strategy vector _s_ (conceptually a vector, but in practice a
% structure)
[s.tdia_exit, s.tdia_enter, s.dtegg] = ndgrid(tdia_exit, tdia_enter, dtegg);
NS = NDx * NDn * NE; % total number of strategy combinations


% evaluate the full fitness landscape, one chunk of strategies at a time
chunkSize = 1;
ind0 = [(1 : chunkSize : NS) NS+1];
dF1 = nan.*ones([NT NC NS]);
clear dF1chunks
parfor i = 1:length(ind0)-1
	ind = (ind0(i) : ind0(i+1)-1);
	si = selectRows(s,ind);
	dF1chunks{i} = coltrane_integrate(forcing,p,t0,si,'fitness only');
		% dF1 = E N / We
end
for i=1:length(dF1chunks)
	ind = (ind0(i) : ind0(i+1)-1);
	dF1(:,:,ind) = dF1chunks{i};
end
fl = fitnessLandscape(dF1,forcing.t,t0,s);
fl.forcing = forcing;
fl.p = p;


if strcmpi(whatToSave, 'fitness only')
	v = [];
	return;
end


% filter strategy landscape by 2-gen fitness, and rerun model, saving full 
% output only for the fit cohorts and strategies
fit = fl.F2 >= 1;
viableStrategies = find(any(fit,2));
	% s is a fit strategy if F2(t0,s)>1 for some t0
viableCohorts = find(any(fit,3) & t0 <= t0(1)+365);
	% only consider cohorts in the first year
disp([num2str(length(viableStrategies)) ' strategies and ' ...
      num2str(length(viableCohorts)) ' spawning dates selected']);
s = selectRows(s, viableStrategies);
t0 = t0(viableCohorts);
v = coltrane_integrate(forcing,p,t0,s,whatToSave);
v.F1 = fl.F1(1,viableCohorts,viableStrategies);
v.F2 = fl.F2(1,viableCohorts,viableStrategies);
	% copy two-generation fitness over from the full calculation (which
	% included cohorts in all years)




% ------------------------------------------------------------------------------
function si = selectRows(s,ind)
fields = fieldnames(s);
for k=1:length(fields)
	si.(fields{k}) = s.(fields{k})(ind);
end
