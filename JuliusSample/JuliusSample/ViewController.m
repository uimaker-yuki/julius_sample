//
//  ViewController.m
//  JuliusSample
//
//  Created by TAKEUCHI Yutaka on 2018/04/11.
//  Copyright © 2018年 W2S Inc. All rights reserved.
//

#import "ViewController.h"
#import "JuliusUtil.h"

@interface ViewController ()
@property (weak, nonatomic) IBOutlet UILabel *guidanceLabel;
@property (weak, nonatomic) IBOutlet UILabel *recognitionResult;

@property (weak, nonatomic) IBOutlet UIButton *actionButton;

@end

@implementation ViewController
{
    BOOL _isRecognitionInProgress;
    JuliusUtil *_juliusUtil;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    // Do any additional setup after loading the view, typically from a nib.
    
    _isRecognitionInProgress = NO;
    _juliusUtil = [JuliusUtil new];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (IBAction)actionButtonTapped:(id)sender {
    _isRecognitionInProgress = !_isRecognitionInProgress;
    
    if (_isRecognitionInProgress)
    {
        [_guidanceLabel setText:@"喋ってください"];
        [_actionButton setTitle:@"Push button to stop recognition." forState:UIControlStateNormal];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self->_juliusUtil startRecognition];
        });
    }
    else {
        [_guidanceLabel setText:@"待機中"];
        [_actionButton setTitle:@"Push button to start recognition." forState:UIControlStateNormal];
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self->_juliusUtil stopRecognition];
        });
    }
}


@end
