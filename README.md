# Lereldarion Avatar Portal(s) System

### Surfaces
Declare portals on transforms using `PortalSurface` components.
Control portal size and position with the transform.
Portals are either quad or ellipse.
Portals are considered disabled if transform size = 0.

### System core
At its core, the portal system stores its state inside a `RenderTexture` that is updated thanks to a [camera loop](https://github.com/pema99/shader-knowledge/blob/main/camera-loops.md).
At upload time ([NDMF](https://github.com/bdunderscore/ndmf)), the `PortalSystem` component generates a `SkinnedMeshRenderer` at its location, which feeds the camera loop with fresh positions.
This *portal system mesh* contains points at portal positions and *mesh probe* positions (see later).

Typical hierarchy from avatar root :
- Armature, containing transforms for portals with `PortalSurface` declarations
- Avatar Renderers
- `PortalSystem` : generated system mesh renderer. Toggle this `GameObject` to disable the system.
    - `Camera0` : update 1st stage, writes `_Portal_RT0` (temporary)
    - `Camera1` : update 2nd stage, writes `_Portal_RT1`, the system state texture for the frame.

### Mesh support
Portal mesh support is achieved by a combination of *portal-aware shaders* and *mesh probes*.

Mesh probes are trees of points with individual portal states (*world* or in *portal*) that should follow the mesh topology but at small resolution.
The current system generates 1 mesh probe for each skinned bone, and adds an UV map containing the probe id to mesh vertices, so that each vertex can sample the corresponding mesh probe to determine its state.
Some components control probe generation : `PortalMeshProbeMergeChildren`.

Avatar renderers should then combine mesh probe state (from UV id) and camera state found in `_Portal_RT1` to determine if they should be visible or not depending on portal positions.

### Head Chop Replacement
Mesh probes require accurate positions, and camera loop are seemingly run at the time of the main camera.
Thus by default the local avatar mesh would have head chop active (scale=0) and head related positions would be unusable locally (but ok for remotes).
The solution is to disable *head chop* with the `VRCHeadChop` component, and manually implement it with discard in the shader.
For now there is no way to animate it or fine-tune specific parts.

### TODO
- poiyomi integration
- nice visuals. Background from DepthTexture ? Borders with VHS effect ?
- make nice package with instructions from template : https://github.com/vrchat-community/template-package