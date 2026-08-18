function img = eit_set_fixed_clim(img, clim, ref_level)
% EIT_SET_FIXED_CLIM Force an EIDORS image to use a fixed, shared color
% scale instead of auto-scaling to its own min/max.
%
% img = eit_set_fixed_clim(img, clim, ref_level)
%   clim      max absolute deviation from ref_level shown (colour axis
%             runs ref_level +/- clim)
%   ref_level centre of the colour scale (default 0)
%
% Without this, each show_fem/eidors_colourbar call auto-scales to that
% single image's own data range, which makes trials at different
% temperatures visually incomparable (a small, noisy trial can look just
% as "red" as a large, strong one). Setting calc_colours.ref_level/clim
% on every image before plotting fixes all panels to the same scale.

if nargin < 3; ref_level = 0; end
img.calc_colours.ref_level = ref_level;
img.calc_colours.clim = clim;

end
