//
//  JuliusUtil.m
//  JuliusSample
//
//  Created by TAKEUCHI Yutaka on 2018/04/11.
//  Copyright © 2018年 W2S Inc. All rights reserved.
//

#import "JuliusUtil.h"
#import <julius/juliuslib.h>
//#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

#define NUM_BUFFERS 3
#define DOCUMENTS_FOLDER [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]

static short *capturedBuffer;
static int numberSampling;
static dispatch_semaphore_t semaphore;

@implementation JuliusUtil
{
    AudioStreamBasicDescription dataFormat;
    AudioStreamBasicDescription dataFormat4file;
    AudioQueueRef queue;
    AudioQueueBufferRef buffers[NUM_BUFFERS];
    dispatch_source_t   _timer;
    CFURLRef fileURL;
    AudioFileID audioFile;
    SInt64 currentPacket;
}

static void
status_recready(Recog *recog, void *dummy)
{
    NSLog(@"status_recready");
}

static void
status_speaking(Recog *recog, void *dummy)
{
    NSLog(@"status_speaking");
}

static void
status_resultready(Recog *recog, void *dummy)
{
    NSLog(@"status_resultready");
    
    for (const RecogProcess *r = recog->process_list; r; r = r->next) {
        WORD_INFO *winfo = r->lm->winfo;
        for (int n = 0; n < r->result.sentnum; ++n) {
            Sentence *s   = &(r->result.sent[n]);
            WORD_ID *seq = s->word;
            int seqnum   = s->word_num;
            for (int i = 0; i < seqnum; ++i) {
                NSLog(@"result: %s", winfo->woutput[seq[i]]);
            }
        }
    }
}

static int CallbackThunkForMicStandby(int freq, void *pUserData) {
    JuliusUtil *self_ = (__bridge JuliusUtil*)pUserData;
    return [self_ onCallbackMicStandby:freq];
}

static int CallbackThunkForMicBegin(char *arg, void *pUserData) {
    JuliusUtil *self_ = (__bridge JuliusUtil*)pUserData;
    return [self_ onCallbackMicBegin:arg];
}

static int CallbackThunkForMicRead(short *buf, int sampnum, void *pUserData) {
    JuliusUtil *self_ = (__bridge JuliusUtil*)pUserData;
    return [self_ onCallbackMicRead:buf sampnum:sampnum];
}

static void AudioInputCallback(
                               void* inUserData,
                               AudioQueueRef inAQ,
                               AudioQueueBufferRef inBuffer,
                               const AudioTimeStamp *inStartTime,
                               UInt32 inNumberPacketDescriptions,
                               const AudioStreamPacketDescription *inPacketDescs)
{
    JuliusUtil* recorder = (__bridge JuliusUtil*) inUserData;
    memcpy (capturedBuffer, inBuffer->mAudioData, inBuffer->mAudioDataByteSize);
    numberSampling = inNumberPacketDescriptions;
    
    OSStatus status = AudioFileWritePackets(
                          recorder->audioFile,
                          NO,
                          inBuffer->mAudioDataByteSize,
                          inPacketDescs,
                          recorder->currentPacket,
                          &inNumberPacketDescriptions,
                          inBuffer->mAudioData);

    
    if (status == noErr) {
//        NSLog (@"%s: inNumberPacketDescriptions: %d", __FUNCTION__, inNumberPacketDescriptions);
        recorder->currentPacket += inNumberPacketDescriptions;
        AudioQueueEnqueueBuffer(recorder->queue, inBuffer, 0, nil);

//        NSLog(@"currentPacket : %lld  inNumberPacketDescriptions : %d", recorder->currentPacket, inNumberPacketDescriptions);
    }
    else {
        NSLog(@"AudioFileWritePackets failed. status: %d", status);
    }

    dispatch_semaphore_signal(semaphore);
}

-(void) startRecognition
{
    semaphore = dispatch_semaphore_create(0);
    
    int argc = 9;
    char *argv[argc];
    argv[0] = "me";
    argv[1] = "-C";
    NSURL *url = [[NSBundle mainBundle] URLForResource:@"main" withExtension:@"jconf" subdirectory:@"dictation"];
    argv[2] = (char *)[[url path] UTF8String];
    argv[3] = "-C";
    url = [[NSBundle mainBundle] URLForResource:@"am-dnn" withExtension:@"jconf" subdirectory:@"dictation"];
    argv[4] = (char *)[[url path] UTF8String];
    argv[5] = "-dnnconf";
    url = [[NSBundle mainBundle] URLForResource:@"julius" withExtension:@"dnnconf" subdirectory:@"dictation"];
    argv[6] = (char *)[[url path] UTF8String];
    argv[7] = "-input";
    argv[8] = "mic";
    
    for (int i=0; i<argc; i++) {
        NSLog(@"argv[%d]: %s", i, argv[i]);
    }
    Jconf *jconf = j_config_load_args_new(argc, &argv[0]);
    if (!jconf) {
        NSLog(@"j_config_load_args_new failed.");
        return;
    }
    
    Recog *recog = j_create_instance_from_jconf(jconf);
    if (!recog) {
        NSLog(@"j_create_instance_from_jconf failed.");
        return;
    }
    
    /* Register callback function for JuliusSample */
    RegisterCallbackFunction(0, (tCallbackFunction)CallbackThunkForMicStandby, (__bridge void*)self);
    RegisterCallbackFunction(1, (tCallbackFunction)CallbackThunkForMicBegin, (__bridge void*)self);
    RegisterCallbackFunction(2, (tCallbackFunction)CallbackThunkForMicRead, (__bridge void*)self);
    
    /* Julius original callback function */
    callback_add(recog, CALLBACK_EVENT_SPEECH_READY, status_recready, NULL);
    callback_add(recog, CALLBACK_EVENT_SPEECH_START, status_speaking, NULL);
    callback_add(recog, CALLBACK_RESULT, status_resultready, NULL);
    
    // Initialize audio input
    if (j_adin_init(recog) == FALSE) {
        NSLog(@"j_adin_init failed.");
        return;
    }
    
    // output system information to log
    j_recog_info(recog);
    
    // Open input stream and recognize
    switch (j_open_stream(recog, NULL)) {
        case  0: break; // success
        case -1:
        {
            NSLog(@"Error in input stream.");
            return;
        }
        case -2:
        {
            NSLog(@"Failed to begin input stream.");
            return;
        }
    }
    
    // Recognition loop
    int ret = j_recognize_stream(recog);
    if (ret == -1) {
        NSLog(@"j_recognize_stream failed.");
        return;
    }
    
    // exit
    j_close_stream(recog);
    j_recog_free(recog);
}

-(void) stopRecognition
{
    AudioQueueDispose(queue, YES);
    
    for(int i = 0; i < NUM_BUFFERS; i++) {
        AudioQueueFreeBuffer(queue, buffers[i]);
    }
    
    AudioQueueFlush(queue);
    AudioQueueStop(queue, NO);
    AudioFileClose(audioFile);
}

-(int)onCallbackMicStandby:(int)freq
{
    NSLog(@"onCallbackMicStandby freq:%d", freq);

    dataFormat.mSampleRate = freq;
    dataFormat.mFormatID = kAudioFormatLinearPCM;
    dataFormat.mFramesPerPacket = 1;
    dataFormat.mChannelsPerFrame = 1;
    dataFormat.mBytesPerFrame = 2;
    dataFormat.mBytesPerPacket = 2;
    dataFormat.mBitsPerChannel = 16;
    dataFormat.mReserved = 0;
    dataFormat.mFormatFlags =
    kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;

    dataFormat4file.mSampleRate = freq;
    dataFormat4file.mFormatID = kAudioFormatLinearPCM;
    dataFormat4file.mFramesPerPacket = 1;
    dataFormat4file.mChannelsPerFrame = 1;
    dataFormat4file.mBytesPerFrame = 2;
    dataFormat4file.mBytesPerPacket = 2;
    dataFormat4file.mBitsPerChannel = 16;
    dataFormat4file.mReserved = 0;
    dataFormat4file.mFormatFlags =
    kLinearPCMFormatFlagIsBigEndian | kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked;

    return 0;
}

-(int)onCallbackMicBegin:(char*)arg
{
    NSLog(@"onCallbackMicBegin");
    NSString *filePath = [NSString stringWithFormat:@"%@/hoge.aiff", DOCUMENTS_FOLDER];
    fileURL = CFURLCreateFromFileSystemRepresentation(NULL, (const UInt8 *)[filePath UTF8String], [filePath length], NO);

    currentPacket = 0;
    
    OSStatus error = AudioQueueNewInput(&dataFormat, AudioInputCallback,(__bridge void * _Nullable)(self), nil, kCFRunLoopCommonModes, 0, &queue);
    
    if (error) {
        NSLog(@"AudioQueueNewInput error:%d", error);
        return -1;
    }
    
    AudioFileCreateWithURL(fileURL, kAudioFileAIFFType, &dataFormat4file, kAudioFileFlags_EraseFile, &audioFile);

    for(int i=0; i < NUM_BUFFERS; i++)
    {
        error = AudioQueueAllocateBuffer(queue, (dataFormat.mSampleRate/10.0f)*dataFormat.mBytesPerFrame, &buffers[i]);
        if (error) {
            NSLog(@"AudioQueueAllocateBuffer error:%d", error);
            return -1;
        }

        error = AudioQueueEnqueueBuffer(queue, buffers[i], 0, nil);
        if (error) {
            NSLog(@"AudioQueueEnqueueBuffer error:%d", error);
            return -1;
        }
    }
    
    error = AudioQueueStart(queue, NULL);
    if (error) {
        NSLog(@"AudioQueueStart error:%d", error);
        return -1;
    }

    return 0;
}

-(int)onCallbackMicRead:(short*)buf sampnum:(int)sampnum
{
//    NSLog (@"%s: buf: %p sampnum: %d", __FUNCTION__, buf, sampnum);
    capturedBuffer = buf;
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);

    return numberSampling;
}
@end
