function fmdl = eit_apply_physical_electrode_order(fmdl, nElec)
% EIT_APPLY_PHYSICAL_ELECTRODE_ORDER Permute the mesh's electrode array so
% that logical electrode index k (0-based, matching chA/chB in the raw
% data) sits at the PHYSICAL location of real electrode k, not at
% mk_common_model's default location.
%
% mk_common_model('c2d0c',...) (via dm_2d_circ_pt_elecs) places its
% electrode i (0-based) at standard angle 90 - 22.5*i degrees, i.e.
% STARTING AT TOP (+y), going CLOCKWISE.
%
% Confirmed with the experimenter: the physical board has electrode 0 at
% the BOTTOM, numbered COUNTERCLOCKWISE, i.e. real electrode k sits at
% standard angle -90 + 22.5*k degrees.
%
% Solving 90 - 22.5*i == -90 + 22.5*k (mod 360) for i gives
%   i = mod(8 - k, 16)
% i.e. real electrode k must be placed at the mesh location mk_common_model
% originally built for its OWN electrode index mod(8-k,16). This is applied
% here by permuting fmdl.electrode (which carries the mesh node/z_contact
% assignment -- the geometry), so every OTHER part of the pipeline (stim
% patterns built by plain index, chA/chB lookups) is unaffected and stays
% correct automatically.
%
% Without this fix, localization tested against known heat-source
% positions (20260806 off-center dataset) showed reconstructed peaks
% consistent with an electrode-order mismatch (median error 2.4cm,
% dropping toward ~0.8cm under an x/y-swap-shaped transform) -- this
% permutation is the principled fix, not a curve-fit correction.

if nargin < 2 || isempty(nElec); nElec = 16; end
if numel(fmdl.electrode) ~= nElec
    error('eit_apply_physical_electrode_order:badCount', ...
        'Expected %d electrodes, found %d', nElec, numel(fmdl.electrode));
end

oldElectrode = fmdl.electrode;
newElectrode = oldElectrode;
for k = 0:nElec-1
    oldIdx0 = mod(8 - k, nElec);  % 0-based index into mk_common_model's own layout
    newElectrode(k+1) = oldElectrode(oldIdx0 + 1);
end
fmdl.electrode = newElectrode;

end
