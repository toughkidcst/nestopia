/*
 Copyright (c) 2009, OpenEmu Team
 
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
     * Redistributions of source code must retain the above copyright
       notice, this list of conditions and the following disclaimer.
     * Redistributions in binary form must reproduce the above copyright
       notice, this list of conditions and the following disclaimer in the
       documentation and/or other materials provided with the distribution.
     * Neither the name of the OpenEmu Team nor the
       names of its contributors may be used to endorse or promote products
       derived from this software without specific prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY OpenEmu Team ''AS IS'' AND ANY
 EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL OpenEmu Team BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
  LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
  SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#import "util.h"
#import "OEGameAudio.h"
#import "NESGameCore.h"
#import "TPCircularBuffer.h"
#import "OERingBuffer.h"

typedef struct
{
    TPCircularBuffer *buffer;
    int channelCount;
} OEGameAudioContext;

ExtAudioFileRef recordingFile;

static void StretchSamples(int16_t *outBuf, const int16_t *inBuf,
                           int outFrames, int inFrames, int channels)
{
    int frame;
    float ratio = outFrames / (float)inFrames;
    
    for (frame = 0; frame < outFrames; frame++) {
        float iFrame = frame / ratio, iFrameF = floorf(iFrame);
        float lerp = iFrame - iFrameF;
        int iFrameI = iFrameF;
        int ch;
        
        for (ch = 0; ch < channels; ch++) {
            int a, b, c;
            
            a = inBuf[(iFrameI+0)*channels+ch];
            b = inBuf[(iFrameI+1)*channels+ch];
            
            c = a + lerp*(b-a);
            c = MAX(c, SHRT_MIN);
            c = MIN(c, SHRT_MAX);
            
            outBuf[frame*channels+ch] = c;
        }
    }
}

OSStatus RenderCallback(void                       *in,
                        AudioUnitRenderActionFlags *ioActionFlags,
                        const AudioTimeStamp       *inTimeStamp,
                        UInt32                      inBusNumber,
                        UInt32                      inNumberFrames,
                        AudioBufferList            *ioData);

OSStatus RenderCallback(void                       *in,
                        AudioUnitRenderActionFlags *ioActionFlags,
                        const AudioTimeStamp       *inTimeStamp,
                        UInt32                      inBusNumber,
                        UInt32                      inNumberFrames,
                        AudioBufferList            *ioData)
{
    OEGameAudioContext *context = (OEGameAudioContext*)in;
    int availableBytes = 0;
    void *head = TPCircularBufferTail(context->buffer, &availableBytes);
    int bytesRequested = inNumberFrames * sizeof(SInt16) * context->channelCount;
    availableBytes = MIN(availableBytes, bytesRequested);
    int leftover = bytesRequested - availableBytes;
    char *outBuffer = ioData->mBuffers[0].mData;

    if (leftover > 0) {
        // time stretch
        // FIXME this works a lot better with a larger buffer
        int framesRequested = inNumberFrames;
        int framesAvailable = availableBytes / (sizeof(SInt16) * context->channelCount);
        StretchSamples((int16_t*)outBuffer, head, framesRequested, framesAvailable, context->channelCount);
    } else {
        memcpy(outBuffer, head, availableBytes);
    }
    
    
    TPCircularBufferConsume(context->buffer, availableBytes);
    return noErr;
}

@interface OEGameAudio ()
{
    OEGameAudioContext *_context;
}
@end

@implementation OEGameAudio

// No default version for this class
- (id)init
{
    return nil;
}

// Designated Initializer
- (id)initWithCore:(NESGameCore *)core
{
    self = [super init];
    if(self != nil)
    {
        gameCore = core;
    }
    
    return self;
}

- (void)dealloc
{
    if (_context)
        free(_context);
    AUGraphUninitialize(mGraph);
    //FIXME: added this line tonight.  do we need it?  Fuckety fuck fucking shitty Core Audio documentation... :X
    DisposeAUGraph(mGraph);
}

- (void)pauseAudio
{
    DLog(@"Stopped audio");
    [self stopAudio];
}

- (void)startAudio
{
    [self createGraph];
}

- (void)stopAudio
{
    ExtAudioFileDispose(recordingFile);
    AUGraphStop(mGraph);
    AUGraphClose(mGraph);
    AUGraphUninitialize(mGraph);
}

- (void)createGraph
{
    OSStatus err;
    
    AUGraphStop(mGraph);
    AUGraphClose(mGraph);
    AUGraphUninitialize(mGraph);
    
    //Create the graph
    err = NewAUGraph(&mGraph);
    if(err) NSLog(@"NewAUGraph failed");
    
    ComponentDescription desc;
    
    desc.componentType         = kAudioUnitType_Output;
    desc.componentSubType      = kAudioUnitSubType_DefaultOutput;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;
    desc.componentFlagsMask    = 0;
    desc.componentFlags        = 0;

    //Create the output node
    err = AUGraphAddNode(mGraph, (const AudioComponentDescription *)&desc, &mOutputNode);
    if(err) NSLog(@"couldn't create node for output unit");
    
    err = AUGraphNodeInfo(mGraph, mOutputNode, NULL, &mOutputUnit);
    if(err) NSLog(@"couldn't get output from node");
    
    
    desc.componentType = kAudioUnitType_Mixer;
    desc.componentSubType = kAudioUnitSubType_StereoMixer;
    desc.componentManufacturer = kAudioUnitManufacturer_Apple;

    //Create the mixer node
    err = AUGraphAddNode(mGraph, (const AudioComponentDescription *)&desc, &mMixerNode);
    if(err) NSLog(@"couldn't create node for file player");
    
    err = AUGraphNodeInfo(mGraph, mMixerNode, NULL, &mMixerUnit);
    if(err) NSLog(@"couldn't get player unit from node");

    if (_context)
        free(_context);
    _context = malloc(sizeof(OEGameAudioContext));

    // TODO: seems x86_64 does not work with the converter AU node
    if (0) {
        *_context = (OEGameAudioContext){&(gameCore.ringBuffer->buffer), gameCore.channelCount};

        desc.componentType = kAudioUnitType_FormatConverter;
        desc.componentSubType = kAudioUnitSubType_AUConverter;
        desc.componentManufacturer = kAudioUnitManufacturer_Apple;

        //Create the converter node
        err = AUGraphAddNode(mGraph, (const AudioComponentDescription *)&desc, &mConverterNode);
        if(err)  NSLog(@"couldn't create node for converter");
        
        err = AUGraphNodeInfo(mGraph, mConverterNode, NULL, &mConverterUnit);
        if(err) NSLog(@"couldn't get player unit from converter");
        
        AURenderCallbackStruct renderStruct;
        renderStruct.inputProc = RenderCallback;
        renderStruct.inputProcRefCon = _context;
        
        err = AudioUnitSetProperty(mConverterUnit, kAudioUnitProperty_SetRenderCallback,
                                   kAudioUnitScope_Input, 0, &renderStruct, sizeof(AURenderCallbackStruct));
        if(err) DLog(@"Couldn't set the render callback");
        else DLog(@"Set the render callback");
        
        AudioStreamBasicDescription mDataFormat;
        NSUInteger channelCount = _context->channelCount;
        mDataFormat.mSampleRate       = gameCore.audioSampleRate;
        mDataFormat.mFormatID         = kAudioFormatLinearPCM;
        mDataFormat.mFormatFlags      = kLinearPCMFormatFlagIsSignedInteger | kAudioFormatFlagsNativeEndian;
        mDataFormat.mBytesPerPacket   = 2 * channelCount;
        mDataFormat.mFramesPerPacket  = 1; // this means each packet in the AQ has two samples, one for each channel -> 4 bytes/frame/packet
        mDataFormat.mBytesPerFrame    = 2 * channelCount;
        mDataFormat.mChannelsPerFrame = channelCount;
        mDataFormat.mBitsPerChannel   = 16;
        
        err = AudioUnitSetProperty(mConverterUnit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &mDataFormat, sizeof(AudioStreamBasicDescription));
        if (err) NSLog(@"couldn't set player's input stream format");
        

        err = AUGraphConnectNodeInput(mGraph, mConverterNode, 0, mMixerNode, 0);
        if (err) NSLog(@"Couldn't connect the converter to the mixer");
    }
    // connect the player to the output unit (stream format will propagate)
    //Open the graph
    err = AUGraphOpen(mGraph);
    if(err) NSLog(@"couldn't open graph");
    
    err = AUGraphConnectNodeInput(mGraph, mMixerNode, 0, mOutputNode, 0);
    if(err) NSLog(@"Could not connect the input of the output");
    
    
    //AudioUnitSetParameter(mOutputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, [[[GameDocumentController sharedDocumentController] preferenceController] volume] ,0);
    err = AudioUnitSetParameter(mOutputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, 1.0 ,0);
    if (err) NSLog(@"couldn't set parameter");

    err = AUGraphUpdate(mGraph, NULL);
    if (err) NSLog(@"couldn't update graph");

    err = AUGraphInitialize(mGraph);
    if (err) NSLog(@"couldn't initialize graph");
    
    err = AUGraphStart(mGraph);
    if (err) NSLog(@"couldn't start graph");
	
        //    CFShow(mGraph);
    [self setVolume:[self volume]];
}

- (float)volume
{
    return volume;
}

- (void)setVolume:(float)aVolume
{
    volume = aVolume;
    if (mOutputUnit)
        AudioUnitSetParameter(mOutputUnit, kAudioUnitParameterUnit_LinearGain, kAudioUnitScope_Global, 0, volume, 0);
}

@end
