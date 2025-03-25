//
//  DotMFMManager.h
//  DotSdk
//
//  Created by Jayson on 2020/5/22.
//  Copyright © 2023 Movella. All rights reserved.
//

/**
 * The Dot MFM  manager class
 */
#import <Foundation/Foundation.h>
#import <MovellaDotSdk/DotDevice.h>
#import <MovellaDotSdk/DotDefine.h>

/**
 * The DotMFMManager's delegate that can update MFM progress and status
 */
@protocol DotMFMDelegate <NSObject>

@optional
/**
 * When call  startMFM  this method will be triggered.
 * @param progress The MFM progress
 * @param address The DotDevice address
 */
- (void)onMFMProgress:(int)progress address:(NSString *_Nullable)address;

/**
 * When  MFM process completed  this method will be triggered.
 * @param type The MFM result satus
 * @param address The DotDevice address
 */
- (void)onMFMCompleted:(XSDotMFMResultTpye) type address:(NSString *_Nullable)address;

@end

NS_ASSUME_NONNULL_BEGIN

@interface DotMFMManager : NSObject

/**
 * The DotMFMDelegate property, set mfmDelegate before call startMFM
 */
@property (weak, nonatomic) id<DotMFMDelegate> mfmDelegate;

/**
 * Get default DotMFMManager object
 */
@property (readonly, strong, class) DotMFMManager *defaultManager;

/**
 * Start MFM
 * @param devices The DotDevice object list
 */
- (void)startMFM:(NSArray <DotDevice *>*)devices;

/**
 * Stop MFM
 * @param devices The DotDevice object list
 */
- (void)stopMFM:(NSArray <DotDevice *>*)devices;

@end

NS_ASSUME_NONNULL_END
