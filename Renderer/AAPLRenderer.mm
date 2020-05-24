/*
See LICENSE folder for this sample’s licensing information.

Abstract:
Implementation of a platform independent renderer class, which performs Metal setup and per frame rendering
*/

@import simd;
@import MetalKit;

#import "AAPLRenderer.h"
# include <TargetConditionals.h>

// Header shared between C code here, which executes Metal API commands, and .metal files, which
// uses these types as inputs to the shaders.
#import "AAPLShaderTypes.h"
#include <mdk/Player.h>
#include <mdk/RenderAPI.h>
using namespace MDK_NS;
#define DRAW_TWICE 0

// Main class performing the rendering
@implementation AAPLRenderer
{
    id<MTLDevice> _device;

    // The render pipeline generated from the vertex and fragment shaders in the .metal shader file.
    id<MTLRenderPipelineState> _pipelineState;

    // The command queue used to pass commands to the device.
    id<MTLCommandQueue> _commandQueue;

    // The current size of the view, used as an input to the vertex shader.
    vector_uint2 _viewportSize;

    Player player;
}

- (nonnull instancetype)initWithMetalKitView:(nonnull MTKView *)mtkView
{
    self = [super init];
    if(self)
    {
        NSError *error;

        _device = mtkView.device;

        // Load all the shader files with a .metal file extension in the project.
        id<MTLLibrary> defaultLibrary = [_device newDefaultLibrary];

        id<MTLFunction> vertexFunction = [defaultLibrary newFunctionWithName:@"vertexShader"];
        id<MTLFunction> fragmentFunction = [defaultLibrary newFunctionWithName:@"fragmentShader"];

        // Configure a pipeline descriptor that is used to create a pipeline state.
        MTLRenderPipelineDescriptor *pipelineStateDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
        pipelineStateDescriptor.label = @"Simple Pipeline";
        pipelineStateDescriptor.vertexFunction = vertexFunction;
        pipelineStateDescriptor.fragmentFunction = fragmentFunction;
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = mtkView.colorPixelFormat;

        _pipelineState = [_device newRenderPipelineStateWithDescriptor:pipelineStateDescriptor
                                                                 error:&error];
                
        // Pipeline State creation could fail if the pipeline descriptor isn't set up properly.
        //  If the Metal API validation is enabled, you can find out more information about what
        //  went wrong.  (Metal API validation is enabled by default when a debug build is run
        //  from Xcode.)
        NSAssert(_pipelineState, @"Failed to create pipeline state: %@", error);

        // Create the command queue
        _commandQueue = [_device newCommandQueue];
    }

    MetalRenderAPI ra;
    ra.device = (__bridge void*)_device;
    ra.cmdQueue = (__bridge void*)_commandQueue;
    ra.opaque = (__bridge void*)mtkView;
    ra.currentRenderTarget = [](void* opaque){
        auto view = (__bridge MTKView*)opaque;
        return (__bridge void*)view.currentDrawable.texture;
    };
    player.setRenderAPI(&ra);
    player.setVideoDecoders({"VT", "FFmpeg"});
    player.setMedia("/Users/wangbin/Movies/newyear.mp4");
    player.setState(State::Playing);
    return self;
}

/// Called whenever view changes orientation or is resized
- (void)mtkView:(nonnull MTKView *)view drawableSizeWillChange:(CGSize)size
{
    // Save the size of the drawable to pass to the vertex shader.
    _viewportSize.x = size.width;
    _viewportSize.y = size.height;
    player.setVideoSurfaceSize(_viewportSize.x, _viewportSize.y);
    player.setLoop(-1);
}

/// Called whenever the view needs to render a frame.
- (void)drawInMTKView:(nonnull MTKView *)view
{
#if 0 // call setRenderAPI() when target texture changed. or set MetalRenderAPI.currentRenderTarget callback and setRenderAPI() once
    MetalRenderAPI ra;
    ra.device = (__bridge void*)_device;
    ra.cmdQueue = (__bridge void*)_commandQueue;
    ra.texture = (__bridge void*)view.currentDrawable.texture;
    player.setRenderAPI(&ra);
#endif
#if DRAW_TWICE
    player.setBackgroundColor(1.0, 0.0, 0.0, 1.0); // set once is enough. here we draw multiple times in different viewports
    player.setVideoSurfaceSize(_viewportSize.x, _viewportSize.y); // set once when size changed is enough for most use cases. here we draw multiple times in different viewports
#endif
    player.renderVideo();
    static const AAPLVertex triangleVertices[] =
    {
        // 2D positions,    RGBA colors
        { {  250,  -250 }, { 1, 0, 0, 1 } },
        { { -250,  -250 }, { 0, 1, 0, 1 } },
        { {    0,   250 }, { 0, 0, 1, 1 } },
    };

    // Create a new command buffer for each render pass to the current drawable.
    id<MTLCommandBuffer> commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"MyCommand";

    // Obtain a renderPassDescriptor generated from the view's drawable textures.
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    renderPassDescriptor.colorAttachments[0].loadAction = MTLLoadActionLoad; // do not clear rendered video

    if(renderPassDescriptor != nil)
    {
        // Create a render command encoder.
        id<MTLRenderCommandEncoder> renderEncoder =
        [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"MyRenderEncoder";

        // Set the region of the drawable to draw into.
        [renderEncoder setViewport:(MTLViewport){0.0, 0.0, (double)_viewportSize.x, (double)_viewportSize.y, 0.0, 1.0 }];
        
        [renderEncoder setRenderPipelineState:_pipelineState];

        // Pass in the parameter data.
        [renderEncoder setVertexBytes:triangleVertices
                               length:sizeof(triangleVertices)
                              atIndex:AAPLVertexInputIndexVertices];
        
        [renderEncoder setVertexBytes:&_viewportSize
                               length:sizeof(_viewportSize)
                              atIndex:AAPLVertexInputIndexViewportSize];

        // Draw the triangle.
        [renderEncoder drawPrimitives:MTLPrimitiveTypeTriangle
                          vertexStart:0
                          vertexCount:3];

        [renderEncoder endEncoding];
#if !DRAW_TWICE
        // Schedule a present once the framebuffer is complete using the current drawable.
        [commandBuffer presentDrawable:view.currentDrawable];
#endif
    }

    // Finalize rendering here & push the command buffer to the GPU.
    [commandBuffer commit];
#if DRAW_TWICE
    player.setBackgroundColor(-1.0, -1.0, -1.0, -1.0); // setting an invalid color will draw on the background instead of clear first
    player.setVideoSurfaceSize(_viewportSize.x/2, _viewportSize.y/2); // set once when size changed is enough for most use cases. here we draw multiple times in different viewports
    player.renderVideo();

    commandBuffer = [_commandQueue commandBuffer];
    commandBuffer.label = @"present";
    [commandBuffer presentDrawable:view.currentDrawable];
    [commandBuffer commit];
#endif
}

@end
