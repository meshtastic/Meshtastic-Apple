#!/usr/bin/env -S uv run --script
# /// script
# dependencies = [
#   "resvg-py",
#   "numpy",
#   "scipy",
#   "pillow",
#   "scikit-image",
#   "matplotlib",
#   "usd-core",
# ]
# ///
"""Builds the banana that stands beside a model on the cinema's stand, for scale.

    uv run scripts/cinema/banana_for_scale.py

The drawing, drawings/banana_icon.svg ("Banana icon" by Keistutis on Openclipart, CC0), is
rendered without its drop shadow and stood on end, stem up. Its outline is inflated into a round
banana at real size, and the rendered drawing is laid on its front and back. It writes
Packages/CinemaContent/Sources/CinemaContent/Props/banana_for_scale.usdz.
"""

import io
import os
import tempfile

import numpy as np
import resvg_py
from matplotlib.path import Path as Outline
from PIL import Image
from pxr import Gf, Sdf, Usd, UsdGeom, UsdShade, UsdUtils
from scipy import ndimage
from scipy.spatial import Delaunay
from skimage import measure

HERE = os.path.dirname(os.path.abspath(__file__))
DRAWING = os.path.join(HERE, "drawings", "banana_icon.svg")
OUT = os.path.join(HERE, "..", "..", "Packages", "CinemaContent", "Sources", "CinemaContent", "Props", "banana_for_scale.usdz")

# Tip to the top of the stem, standing up: a medium banana.
HEIGHT_M = 0.185
# Pixels between the mesh's inside points, about a millimeter.
GRID = 10
COPYRIGHT = ("Made for Meshtastic from \"Banana icon\" by Keistutis, Openclipart, "
             "dedicated to the public domain (CC0).")


def render():
    """The drawing as RGBA, without the shadow under it, turned so the stem is at the top."""
    svg = open(DRAWING).read()
    shadow = 'style="fill:url(#radialGradient3907)"'
    if shadow not in svg:
        raise SystemExit("the drawing's shadow (radialGradient3907) wasn't found; check the drawing")
    svg = svg.replace(shadow, 'style="display:none;fill:url(#radialGradient3907)"')
    png = bytes(resvg_py.svg_to_bytes(svg_string=svg, width=2048))
    image = np.asarray(Image.open(io.BytesIO(png)).convert("RGBA"))
    # It lies with the stem at the top left; a quarter turn clockwise stands it up, stem on top.
    return np.rot90(image, k=-1).copy()


def silhouette(image):
    """The banana's shape: the solid part of the drawing, its soft blurred edges left out."""
    mask = image[:, :, 3] > 170
    labels, count = ndimage.label(mask)
    sizes = ndimage.sum(mask, labels, range(1, count + 1))
    mask = labels == (int(np.argmax(sizes)) + 1)
    return ndimage.binary_fill_holes(mask)


def build():
    image = render()
    mask = silhouette(image)
    rows, cols = np.nonzero(mask)
    meters_per_px = HEIGHT_M / (rows.max() - rows.min())
    # Cropped to the banana with a margin, so the texture is all banana.
    pad = 8
    top, left = max(rows.min() - pad, 0), max(cols.min() - pad, 0)
    bottom, right = min(rows.max() + pad, mask.shape[0] - 1), min(cols.max() + pad, mask.shape[1] - 1)
    image, mask = image[top:bottom + 1, left:right + 1], mask[top:bottom + 1, left:right + 1]
    h, w = mask.shape

    # Round in section: at each point, the height of a circle as wide as the banana is there.
    inside = ndimage.distance_transform_edt(mask)
    half_width = ndimage.maximum_filter(inside, size=int(inside.max() * 2.2))
    depth = np.sqrt(np.clip(2 * inside * half_width - inside ** 2, 0, None))

    # The outline, and points on a grid inside it, kept clear of the outline so no triangle is
    # a sliver; triangles between them.
    contour = max(measure.find_contours(mask.astype(float), 0.5), key=len)
    contour = measure.approximate_polygon(contour, tolerance=0.6)[:-1]
    gy, gx = np.mgrid[GRID / 2:h:GRID, GRID / 2:w:GRID]
    grid = np.column_stack([gy.ravel(), gx.ravel()])
    cells = grid.astype(int)
    grid = grid[inside[cells[:, 0], cells[:, 1]] > GRID * 0.6]
    points = np.vstack([contour, grid])  # (row, column)
    edge = len(contour)
    triangles = Delaunay(points[:, ::-1]).simplices
    centers = points[triangles].mean(axis=1)
    faces = triangles[Outline(contour[:, ::-1]).contains_points(centers[:, ::-1])]

    # The front and back meet at the outline, where the banana has no depth.
    z = ndimage.map_coordinates(depth, points.T, order=1) * meters_per_px
    z[:edge] = 0
    count = len(points)
    x = (points[:, 1] - w / 2) * meters_per_px
    y = (h - 1 - points[:, 0]) * meters_per_px
    vertices = np.vstack([np.column_stack([x, y, z]), np.column_stack([x, y, -z])[edge:]])
    back = np.concatenate([np.arange(edge), np.arange(count, 2 * count - edge)])
    faces = np.vstack([faces, back[faces][:, ::-1]])
    uv = np.column_stack([points[:, 1] / (w - 1), 1 - points[:, 0] / (h - 1)])
    uvs = np.vstack([uv, uv[edge:]])
    # Stood on its lowest point, centered across and front to back.
    vertices[:, 1] -= vertices[:, 1].min()
    vertices[:, 0] -= (vertices[:, 0].min() + vertices[:, 0].max()) / 2

    normals = smooth_normals(vertices, faces)
    # Faces wound so the front's normals point back would light it from inside: turn them all.
    if normals[edge:count, 2].mean() < 0:
        faces = faces[:, ::-1]
        normals = -normals

    # The drawing as the texture, its see-through edges filled with the nearest banana color so
    # the rim doesn't pick up black.
    rgb = image[:, :, :3]
    solid = image[:, :, 3] > 40
    nearest = ndimage.distance_transform_edt(~solid, return_distances=False, return_indices=True)
    texture = Image.fromarray(rgb[nearest[0], nearest[1]].astype(np.uint8), "RGB")
    return vertices, normals, uvs, faces, texture


def smooth_normals(vertices, faces):
    corners = vertices[faces]
    face_normals = np.cross(corners[:, 1] - corners[:, 0], corners[:, 2] - corners[:, 0])
    normals = np.zeros_like(vertices)
    for k in range(3):
        np.add.at(normals, faces[:, k], face_normals)
    lengths = np.linalg.norm(normals, axis=1, keepdims=True)
    return normals / np.where(lengths > 0, lengths, 1)


def write(vertices, normals, uvs, faces, texture, out):
    name = "BananaForScale"
    with tempfile.TemporaryDirectory() as folder:
        texture.save(os.path.join(folder, "banana_peel.png"))
        usdc = os.path.join(folder, name + ".usdc")
        stage = Usd.Stage.CreateNew(usdc)
        UsdGeom.SetStageUpAxis(stage, UsdGeom.Tokens.y)
        UsdGeom.SetStageMetersPerUnit(stage, 1.0)
        layer = stage.GetRootLayer()
        layer.documentation = COPYRIGHT
        layer.customLayerData = {"copyright": COPYRIGHT, "source": "https://openclipart.org/detail/189457/banana"}
        root = UsdGeom.Xform.Define(stage, f"/{name}")
        stage.SetDefaultPrim(root.GetPrim())
        Usd.ModelAPI(root.GetPrim()).SetKind("component")

        material = UsdShade.Material.Define(stage, f"/{name}/Materials/Peel")
        surface = UsdShade.Shader.Define(stage, f"/{name}/Materials/Peel/Surface")
        surface.CreateIdAttr("UsdPreviewSurface")
        surface.CreateInput("roughness", Sdf.ValueTypeNames.Float).Set(0.5)
        surface.CreateInput("metallic", Sdf.ValueTypeNames.Float).Set(0.0)
        reader = UsdShade.Shader.Define(stage, f"/{name}/Materials/Peel/UV")
        reader.CreateIdAttr("UsdPrimvarReader_float2")
        reader.CreateInput("varname", Sdf.ValueTypeNames.Token).Set("st")
        reader.CreateOutput("result", Sdf.ValueTypeNames.Float2)
        picture = UsdShade.Shader.Define(stage, f"/{name}/Materials/Peel/Picture")
        picture.CreateIdAttr("UsdUVTexture")
        picture.CreateInput("file", Sdf.ValueTypeNames.Asset).Set("banana_peel.png")
        picture.CreateInput("sourceColorSpace", Sdf.ValueTypeNames.Token).Set("sRGB")
        picture.CreateInput("st", Sdf.ValueTypeNames.Float2).ConnectToSource(reader.ConnectableAPI(), "result")
        picture.CreateOutput("rgb", Sdf.ValueTypeNames.Float3)
        surface.CreateInput("diffuseColor", Sdf.ValueTypeNames.Color3f).ConnectToSource(picture.ConnectableAPI(), "rgb")
        material.CreateSurfaceOutput().ConnectToSource(surface.ConnectableAPI(), "surface")

        mesh = UsdGeom.Mesh.Define(stage, f"/{name}/Banana")
        mesh.CreatePointsAttr(vertices.astype(np.float32))
        mesh.CreateFaceVertexCountsAttr(np.full(len(faces), 3, dtype=np.int32))
        mesh.CreateFaceVertexIndicesAttr(faces.flatten().astype(np.int32))
        mesh.CreateNormalsAttr(normals.astype(np.float32))
        mesh.SetNormalsInterpolation(UsdGeom.Tokens.vertex)
        mesh.CreateSubdivisionSchemeAttr(UsdGeom.Tokens.none)
        mesh.CreateExtentAttr([Gf.Vec3f(*vertices.min(axis=0)), Gf.Vec3f(*vertices.max(axis=0))])
        st = UsdGeom.PrimvarsAPI(mesh.GetPrim()).CreatePrimvar("st", Sdf.ValueTypeNames.TexCoord2fArray, UsdGeom.Tokens.vertex)
        st.Set(uvs.astype(np.float32))
        UsdShade.MaterialBindingAPI.Apply(mesh.GetPrim()).Bind(material)
        layer.Save()
        os.makedirs(os.path.dirname(out), exist_ok=True)
        # Packaged from the stage's folder, so the texture it names is found and goes in with it.
        here = os.getcwd()
        os.chdir(folder)
        try:
            ok = UsdUtils.CreateNewARKitUsdzPackage(usdc, os.path.abspath(os.path.join(here, out)) if not os.path.isabs(out) else out)
        finally:
            os.chdir(here)
    if not ok:
        raise SystemExit(f"failed to package {out}")


def main():
    vertices, normals, uvs, faces, texture = build()
    out = os.path.normpath(OUT)
    write(vertices, normals, uvs, faces, texture, out)
    size = (vertices.max(axis=0) - vertices.min(axis=0)) * 1000
    print(f"{out}: {size[0]:.0f} × {size[1]:.0f} × {size[2]:.0f} mm, {len(vertices)} points, "
          f"{len(faces)} triangles, {os.path.getsize(out) // 1024} KB")


if __name__ == "__main__":
    main()
