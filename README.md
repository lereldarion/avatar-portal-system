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

Mesh probes form trees.
The main armature will be rooted at the head bone (which **must** be defined) to closely match main camera.
An incoherent system state can happen where mesh head state is different from local head camera state.
In this case, to best follow what others see, local camera state will be set to head mesh state.

### Head Chop Replacement
Mesh probes require accurate positions, and camera loop are seemingly run at the time of the main camera.
Thus by default the local avatar mesh would have head chop active (scale=0) and head related positions would be unusable locally (but ok for remotes).
The solution is to disable *head chop* with the `VRCHeadChop` component, and manually implement it with discard in the shader.
For now there is no way to animate it or fine-tune specific parts.

Head chop uses `is_local` from header so it fails if the system is never enabled.
Ths alternative would be to animate it on every relevant renderer... annoying.

### TODO

Portal surface lag discards bug
- Conditions : VR, camera in world, object in world in front of portal background
- Waving hand in this condition : incoherent border of objects that "lag" and show through the world.
- Grabpass from last frame ? Stereo Offsets lagging ? Only in VR SPS-I
- Forcing reset buffer on cameras does not change anything for both
- Was not fixed by camera order fix for data lag bug
- Disabling stencil has no effect
- Mirror can generate transitory artifacts. VR tests : large artifacts clearly due to mirror. Disabling alpha in mirror does not fix.
- TODO Investigate mirror frame structure with frame analyzer

Normal TODOs
- shadowcaster setup is not good : try to think of a semantic that works
- maybe try to support mirrors ; for now the avatar show as without any portal system in mirrors.
- poiyomi integration
- nice visuals. Background from DepthTexture ? Borders with VHS effect ?
- make nice package with instructions from template : https://github.com/vrchat-community/template-package