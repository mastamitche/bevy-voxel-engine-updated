use crate::{
    load::{GridHierarchy, Pallete},
    LoadVoxelWorld,
};
use bevy::{
    prelude::*,
    render::{
        extract_resource::{ExtractResource, ExtractResourcePlugin},
        render_resource::*,
        renderer::{RenderDevice, RenderQueue},
        Render, RenderApp, RenderSet,
    },
};
use std::{num::NonZeroU32, sync::Arc};

pub struct VoxelWorldPlugin;

impl Plugin for VoxelWorldPlugin {
    fn build(&self, _app: &mut App) {}

    fn finish(&self, app: &mut App) {
        let render_device = app.sub_app(RenderApp).world().resource::<RenderDevice>();

        let render_queue = app.sub_app(RenderApp).world().resource::<RenderQueue>();

        let gh = GridHierarchy::empty(256);
        let buffer_size = gh.get_buffer_size();
        let texture_size = gh.texture_size;
        let gh_offsets = gh.get_offsets();

        let mut levels = [UVec4::ZERO; 8];
        let mut offsets = [UVec4::ZERO; 8];
        for i in 0..8 {
            levels[i] = UVec4::new(gh.levels[i], 0, 0, 0);
            offsets[i] = UVec4::new(gh_offsets[i], 0, 0, 0);
        }

        // Uniforms
        let voxel_uniforms = VoxelUniforms {
            pallete: gh.pallete.into(),
            portals: [ExtractedPortal::default(); 32],
            levels,
            offsets,
            texture_size,
            world_size: texture_size * 3,
            chunk_size: texture_size, // Set an appropriate chunk size
            active_chunks: [ChunkInfo::default(); 27], // 3x3x3 grid of chunks
        };
        let mut uniform_buffer = UniformBuffer::from(voxel_uniforms.clone());
        uniform_buffer.write_buffer(&render_device, &render_queue);

        // Storage
        let grid_hierarchy = render_device.create_buffer_with_data(&BufferInitDescriptor {
            contents: &vec![0; buffer_size],
            label: None,
            usage: BufferUsages::STORAGE | BufferUsages::COPY_DST,
        });

        // Sampler
        let texture_sampler = render_device.create_sampler(&SamplerDescriptor {
            mag_filter: FilterMode::Linear,
            min_filter: FilterMode::Linear,
            mipmap_filter: FilterMode::Linear,
            ..default()
        });

        let bind_group_layout = render_device.create_bind_group_layout(
            "voxelization bind group layout",
            &[
                BindGroupLayoutEntry {
                    binding: 0,
                    visibility: ShaderStages::VERTEX_FRAGMENT | ShaderStages::COMPUTE,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: BufferSize::new(VoxelUniforms::SHADER_SIZE.into()),
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 1,
                    visibility: ShaderStages::VERTEX_FRAGMENT | ShaderStages::COMPUTE,
                    ty: BindingType::StorageTexture {
                        access: StorageTextureAccess::ReadWrite,
                        format: TextureFormat::R16Uint,
                        view_dimension: TextureViewDimension::D3,
                    },
                    count: NonZeroU32::new(27), // 3x3x3 grid of chunks
                },
                BindGroupLayoutEntry {
                    binding: 2,
                    visibility: ShaderStages::VERTEX_FRAGMENT | ShaderStages::COMPUTE,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: BufferSize::new(4),
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 3,
                    visibility: ShaderStages::FRAGMENT | ShaderStages::COMPUTE,
                    ty: BindingType::Sampler(SamplerBindingType::Filtering),
                    count: None,
                },
            ],
        );
        let chunk_textures: [TextureView; 27] = std::array::from_fn(|_| {
            let texture = render_device.create_texture_with_data(
                &render_queue,
                &TextureDescriptor {
                    label: None,
                    size: Extent3d {
                        width: voxel_uniforms.chunk_size,
                        height: voxel_uniforms.chunk_size,
                        depth_or_array_layers: voxel_uniforms.chunk_size,
                    },
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: TextureDimension::D3,
                    format: TextureFormat::R16Uint,
                    usage: TextureUsages::STORAGE_BINDING | TextureUsages::COPY_DST,
                    view_formats: &[],
                },
                TextureDataOrder::default(),
                &gh.texture_data.clone(),
            );
            texture.create_view(&TextureViewDescriptor::default())
        });
        let chunk_texture_refs: [&wgpu::TextureView; 27] =
            chunk_textures.each_ref().map(|tv| &**tv);

        let bind_group = render_device.create_bind_group(
            None,
            &bind_group_layout,
            &[
                BindGroupEntry {
                    binding: 0,
                    resource: uniform_buffer.binding().unwrap(),
                },
                BindGroupEntry {
                    binding: 1,
                    resource: BindingResource::TextureViewArray(&chunk_texture_refs),
                },
                BindGroupEntry {
                    binding: 2,
                    resource: grid_hierarchy.as_entire_binding(),
                },
                BindGroupEntry {
                    binding: 3,
                    resource: BindingResource::Sampler(&texture_sampler),
                },
            ],
        );

        app.insert_resource(LoadVoxelWorld::None)
            .insert_resource(NewGridHierarchy::None)
            .insert_resource(voxel_uniforms)
            .add_plugins(ExtractResourcePlugin::<NewGridHierarchy>::default())
            .add_plugins(ExtractResourcePlugin::<VoxelUniforms>::default())
            .add_systems(Update, load_voxel_world);

        let render_app = app.sub_app_mut(RenderApp);

        render_app
            .insert_resource(VoxelData {
                uniform_buffer,
                chunk_textures,
                grid_hierarchy,
                texture_sampler,
                bind_group_layout,
                bind_group,
            })
            .add_systems(Render, prepare_uniforms.in_set(RenderSet::Prepare))
            .add_systems(Render, load_voxel_world_prepare.in_set(RenderSet::Prepare))
            .add_systems(Render, queue_bind_group.in_set(RenderSet::Queue));
    }
}

#[derive(Resource)]
pub struct VoxelData {
    pub uniform_buffer: UniformBuffer<VoxelUniforms>,
    pub chunk_textures: [TextureView; 27],
    pub grid_hierarchy: Buffer,
    pub texture_sampler: Sampler,
    pub bind_group_layout: BindGroupLayout,
    pub bind_group: BindGroup,
}

#[derive(Default, Debug, Clone, Copy, ShaderType)]
pub struct PalleteEntry {
    pub colour: Vec4,
}

impl Into<[PalleteEntry; 256]> for Pallete {
    fn into(self) -> [PalleteEntry; 256] {
        let mut pallete = [PalleteEntry::default(); 256];
        for i in 0..256 {
            pallete[i].colour = self[i].into();
        }
        pallete
    }
}

#[derive(Default, Debug, Clone, Copy, ShaderType)]
pub struct ExtractedPortal {
    pub transformation: Mat4,
    pub position: Vec3,
    pub normal: Vec3,
}

#[derive(Default, Clone, Copy, ShaderType)]
pub struct ChunkInfo {
    pub position: Vec3,
    pub texture_index: u32,
}

#[derive(Resource, ExtractResource, Clone, ShaderType)]
pub struct VoxelUniforms {
    pub pallete: [PalleteEntry; 256],
    pub portals: [ExtractedPortal; 32],
    pub levels: [UVec4; 8],
    pub offsets: [UVec4; 8],
    pub texture_size: u32,
    pub chunk_size: u32,
    pub world_size: u32,
    pub active_chunks: [ChunkInfo; 27],
}
#[derive(Resource, ExtractResource, Clone)]
enum NewGridHierarchy {
    Some(Arc<GridHierarchy>),
    None,
}

fn prepare_uniforms(
    voxel_uniforms: Res<VoxelUniforms>,
    mut voxel_data: ResMut<VoxelData>,
    render_device: Res<RenderDevice>,
    render_queue: Res<RenderQueue>,
) {
    voxel_data.uniform_buffer.set(voxel_uniforms.clone());
    voxel_data
        .uniform_buffer
        .write_buffer(&render_device, &render_queue);
}
fn load_voxel_world(
    mut load_voxel_world: ResMut<LoadVoxelWorld>,
    mut new_gh: ResMut<NewGridHierarchy>,
    mut voxel_uniforms: ResMut<VoxelUniforms>,
) {
    match load_voxel_world.as_ref() {
        LoadVoxelWorld::Empty(_) | LoadVoxelWorld::File(_) => {
            let gh = match load_voxel_world.as_ref() {
                LoadVoxelWorld::Empty(size) => GridHierarchy::empty(*size),
                LoadVoxelWorld::File(path) => {
                    let file = std::fs::read(path).unwrap();
                    GridHierarchy::from_vox(&file).unwrap()
                }
                LoadVoxelWorld::None => unreachable!(),
            };

            let mut levels = [UVec4::ZERO; 8];
            for i in 0..8 {
                levels[i] = UVec4::new(gh.levels[i], 0, 0, 0);
            }

            voxel_uniforms.pallete = gh.pallete.clone().into();
            voxel_uniforms.levels = levels;
            voxel_uniforms.texture_size = gh.texture_size;

            // Initialize active chunks
            for i in 0..27 {
                let x = (i % 3) as f32 - 1.0;
                let y = ((i / 3) % 3) as f32 - 1.0;
                let z = (i / 9) as f32 - 1.0;
                voxel_uniforms.active_chunks[i] = ChunkInfo {
                    position: Vec3::new(x, y, z) * voxel_uniforms.chunk_size as f32,
                    texture_index: i as u32,
                };
            }

            *new_gh = NewGridHierarchy::Some(Arc::new(gh));
            *load_voxel_world = LoadVoxelWorld::None;
        }
        LoadVoxelWorld::None => {
            *new_gh = NewGridHierarchy::None;
        }
    }
}

fn load_voxel_world_prepare(
    mut voxel_data: ResMut<VoxelData>,
    render_device: Res<RenderDevice>,
    render_queue: Res<RenderQueue>,
    new_gh: Res<NewGridHierarchy>,
) {
    if let NewGridHierarchy::Some(gh) = new_gh.as_ref() {
        let buffer_size = gh.get_buffer_size();

        // grid hierarchy
        voxel_data.grid_hierarchy = render_device.create_buffer_with_data(&BufferInitDescriptor {
            contents: &vec![0; buffer_size],
            label: None,
            usage: BufferUsages::STORAGE | BufferUsages::COPY_DST,
        });

        // voxel world
        // let voxel_world =
        // voxel_data.voxel_world = voxel_world.create_view(&TextureViewDescriptor::default());
        let chunk_textures: [TextureView; 27] = std::array::from_fn(|_| {
            let texture = render_device.create_texture_with_data(
                &render_queue,
                &TextureDescriptor {
                    label: None,
                    size: Extent3d {
                        width: gh.texture_size,
                        height: gh.texture_size,
                        depth_or_array_layers: gh.texture_size,
                    },
                    mip_level_count: 1,
                    sample_count: 1,
                    dimension: TextureDimension::D3,
                    format: TextureFormat::R16Uint,
                    usage: TextureUsages::STORAGE_BINDING | TextureUsages::COPY_DST,
                    view_formats: &[],
                },
                TextureDataOrder::default(),
                &gh.texture_data,
            );
            texture.create_view(&TextureViewDescriptor::default())
        });

        voxel_data.chunk_textures = chunk_textures;
    }
}

fn queue_bind_group(render_device: Res<RenderDevice>, mut voxel_data: ResMut<VoxelData>) {
    let chunk_texture_refs: [&wgpu::TextureView; 27] =
        voxel_data.chunk_textures.each_ref().map(|tv| &**tv);

    let bind_group = render_device.create_bind_group(
        None,
        &voxel_data.bind_group_layout,
        &[
            BindGroupEntry {
                binding: 0,
                resource: voxel_data.uniform_buffer.binding().unwrap(),
            },
            BindGroupEntry {
                binding: 1,
                resource: BindingResource::TextureViewArray(&chunk_texture_refs),
            },
            BindGroupEntry {
                binding: 2,
                resource: voxel_data.grid_hierarchy.as_entire_binding(),
            },
            BindGroupEntry {
                binding: 3,
                resource: BindingResource::Sampler(&voxel_data.texture_sampler),
            },
        ],
    );
    voxel_data.bind_group = bind_group;
}
