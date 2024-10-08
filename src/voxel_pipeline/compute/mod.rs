use bevy::{
    asset::embedded_asset,
    prelude::*,
    render::{
        extract_resource::{ExtractResource, ExtractResourcePlugin},
        render_resource::*,
        renderer::{RenderDevice, RenderQueue},
        Render, RenderApp, RenderSet,
    },
    utils::HashMap,
};

pub mod animation;
pub mod automata;
pub mod clear;
pub mod physics;
pub mod rebuild;

const MAX_TYPE_BUFFER_DATA: usize = 1000000; // 4mb

pub struct ComputeResourcesPlugin;

impl Plugin for ComputeResourcesPlugin {
    fn build(&self, app: &mut App) {
        embedded_asset!(app, "src/", "animation.wgsl");
        embedded_asset!(app, "src/", "automata.wgsl");
        embedded_asset!(app, "src/", "clear.wgsl");
        embedded_asset!(app, "src/", "physics.wgsl");
        embedded_asset!(app, "src/", "rebuild.wgsl");
    }

    fn finish(&self, app: &mut App) {
        let render_device = app.sub_app(RenderApp).world().resource::<RenderDevice>();

        let render_queue = app.sub_app(RenderApp).world().resource::<RenderQueue>();

        let mut uniform_buffer = UniformBuffer::from(ComputeUniforms {
            time: 0.0,
            delta_time: 0.0,
        });
        uniform_buffer.write_buffer(&render_device, &render_queue);

        let physics_buffer_gpu = render_device.create_buffer_with_data(&BufferInitDescriptor {
            contents: bytemuck::cast_slice(&vec![0u32; MAX_TYPE_BUFFER_DATA]),
            label: None,
            usage: BufferUsages::STORAGE | BufferUsages::COPY_DST | BufferUsages::COPY_SRC,
        });
        let physics_buffer_cpu = render_device.create_buffer_with_data(&BufferInitDescriptor {
            contents: bytemuck::cast_slice(&vec![0u32; MAX_TYPE_BUFFER_DATA]),
            label: None,
            usage: BufferUsages::COPY_DST | BufferUsages::MAP_READ,
        });
        let animation_buffer = render_device.create_buffer_with_data(&BufferInitDescriptor {
            contents: bytemuck::cast_slice(&vec![0u32; MAX_TYPE_BUFFER_DATA]),
            label: None,
            usage: BufferUsages::STORAGE | BufferUsages::COPY_DST,
        });

        let bind_group_layout = render_device.create_bind_group_layout(
            "compute bind group layout",
            &[
                BindGroupLayoutEntry {
                    binding: 0,
                    visibility: ShaderStages::COMPUTE,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: BufferSize::new(ComputeUniforms::SHADER_SIZE.into()),
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 1,
                    visibility: ShaderStages::COMPUTE,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Storage { read_only: false },
                        has_dynamic_offset: false,
                        min_binding_size: BufferSize::new(4),
                    },
                    count: None,
                },
                BindGroupLayoutEntry {
                    binding: 2,
                    visibility: ShaderStages::COMPUTE,
                    ty: BindingType::Buffer {
                        ty: BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: BufferSize::new(4),
                    },
                    count: None,
                },
            ],
        );

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
                    resource: physics_buffer_gpu.as_entire_binding(),
                },
                BindGroupEntry {
                    binding: 2,
                    resource: animation_buffer.as_entire_binding(),
                },
            ],
        );

        app.insert_resource(PhysicsData {
            dispatch_size: 0,
            buffer_length: 0,
            entities: HashMap::new(),
            physics_buffer_gpu,
            physics_buffer_cpu,
        })
        .insert_resource(AnimationData {
            dispatch_size: 0,
            animation_buffer,
        })
        .add_plugins(ExtractResourcePlugin::<PhysicsData>::default())
        .add_plugins(ExtractResourcePlugin::<AnimationData>::default());

        let render_app = app.sub_app_mut(RenderApp);

        render_app
            .insert_resource(ComputeData {
                bind_group_layout,
                bind_group,
                uniform_buffer,
            })
            .init_resource::<clear::Pipeline>()
            .init_resource::<rebuild::Pipeline>()
            .init_resource::<automata::Pipeline>()
            .init_resource::<physics::Pipeline>()
            .init_resource::<animation::Pipeline>()
            .add_systems(Render, prepare_uniforms.in_set(RenderSet::Prepare));
    }
}

fn prepare_uniforms(
    time: Res<Time>,
    mut compute_data: ResMut<ComputeData>,
    render_device: Res<RenderDevice>,
    render_queue: Res<RenderQueue>,
) {
    let uniforms = ComputeUniforms {
        time: time.elapsed_seconds_f64() as f32,
        delta_time: time.delta_seconds() as f32,
    };
    compute_data.uniform_buffer.set(uniforms);
    compute_data
        .uniform_buffer
        .write_buffer(&render_device, &render_queue);
}

#[derive(Resource, ShaderType)]
struct ComputeUniforms {
    time: f32,
    delta_time: f32,
}

#[derive(Clone, Resource, ExtractResource)]
pub struct PhysicsData {
    pub dispatch_size: u32,
    pub buffer_length: u64,
    pub entities: HashMap<Entity, usize>,
    pub physics_buffer_gpu: Buffer,
    pub physics_buffer_cpu: Buffer,
}

#[derive(Clone, Resource, ExtractResource)]
pub struct AnimationData {
    pub dispatch_size: u32,
    pub animation_buffer: Buffer,
}

#[derive(Resource)]
pub struct ComputeData {
    pub bind_group_layout: BindGroupLayout,
    pub bind_group: BindGroup,
    uniform_buffer: UniformBuffer<ComputeUniforms>,
}
