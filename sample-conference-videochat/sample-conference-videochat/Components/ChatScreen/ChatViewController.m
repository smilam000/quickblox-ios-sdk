//
//  ChatViewController.m
//  sample-conference-videochat
//
//  Created by Injoit on 2/25/19.
//  Copyright © 2019 Quickblox. All rights reserved.
//

#import "ChatViewController.h"
#import "ChatCollectionView.h"
#import "ChatDataSource.h"
#import "InputToolbar.h"
#import "KVOView.h"
#import "HeaderCollectionReusableView.h"
#import "QBChatMessage+QBDateDivider.h"
#import "ChatNotificationCell.h"
#import "ChatIncomingCell.h"
#import "ChatOutgoingCell.h"
#import "ChatAttachmentOutgoingCell.h"
#import "ChatAttachmentIncomingCell.h"
#import "AttachmentUploadBar.h"
#import "ChatResources.h"
#import "UIImage+Chat.h"
#import "UIColor+Chat.h"
#import "UIView+Chat.h"
#import "NSString+Chat.h"
#import "NSURL+Chat.h"
#import "UIImage+fixOrientation.h"
#import "DateUtils.h"
#import "UsersInfoTableViewController.h"
#import "AttachmentDownloadManager.h"
#import "ZoomedAttachmentViewController.h"
#import "SVProgressHUD.h"
#import <Photos/Photos.h>
#import <TTTAttributedLabel/TTTAttributedLabel.h>
#import "Log.h"
#import "QBUUser+Chat.h"
#import "ChatPrivateTitleView.h"
#import "MenuViewController.h"
#import "ParentVideoVC.h"
#import "SDImageCache.h"
#import "CacheManager.h"
#import "DialogsSelectionVC.h"
#import "ChatDateCell.h"
#import "SelectAssetsVC.h"
#import "PhotoAsset.h"
#import "MenuAction.h"
#import "UIViewController+ContextMenu.h"
#import "UIViewController+Alert.h"
#import "CallSettings.h"
#import "CallPermissions.h"
#import "TitleView.h"
#import "ChatCallOutgoingCell.h"
#import "ChatCallIncomingCell.h"
#import "Alert.h"

typedef NS_ENUM(NSUInteger, MessageStatus) {
    MessageStatusSent = 1,
    MessageStatusSending = 2,
    MessageStatusNotSent = 3,
};

typedef void(^DidAddUsers)(void);

static void * kChatKeyValueObservingContext = &kChatKeyValueObservingContext;

const NSUInteger kSystemInputToolbarDebugHeight = 0;
static const NSUInteger widthPadding = 60.0f;
static const CGFloat attachmentBarHeight = 100.0f;
static const NSUInteger maxNumberLetters = 1000;

@interface ChatViewController () <InputToolbarDelegate, UIImagePickerControllerDelegate,
UINavigationControllerDelegate, UIActionSheetDelegate, UIScrollViewDelegate, UITextViewDelegate,
ChatDataSourceDelegate, ChatManagerDelegate, ChatManagerConnectionDelegate, QBChatDelegate, ChatCellDelegate, ChatCollectionViewDelegateFlowLayout, AttachmentBarDelegate, ChatContextMenuProtocol>

@property (nonatomic, strong) QBUUser *currentUser;
@property (strong, nonatomic) NSString *senderDisplayName;
@property (assign, nonatomic) NSUInteger senderID;
@property (strong, nonatomic) DidAddUsers didAddUsers;
@property (weak, nonatomic) IBOutlet ChatCollectionView *collectionView;
@property (weak, nonatomic) IBOutlet InputToolbar *inputToolbar;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *collectionBottomConstraint;
@property (weak, nonatomic) IBOutlet ChatCollectionViewFlowLayout *chatFlowLayout;

@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarHeightConstraint;
@property (weak, nonatomic) IBOutlet NSLayoutConstraint *toolbarBottomLayoutGuide;

@property (strong, nonatomic, readonly) UIImagePickerController *pickerController;

@property (strong, nonatomic) NSIndexPath *selectedIndexPathForMenu;

@property (strong, nonatomic) ChatDataSource *dataSource;
@property (nonatomic, strong) ChatManager *chatManager;

@property (assign, nonatomic) NSTextCheckingTypes enableTextCheckingTypes;

@property (strong, nonatomic) KVOView *systemInputToolbar;

@property (assign, nonatomic) CGFloat offsetY;
@property (assign, nonatomic) CGFloat topContentAdditionalInset;
@property (assign, nonatomic) BOOL isUploading;
@property (assign, nonatomic) BOOL automaticallyScrollsToMostRecentMessage;
@property (assign, nonatomic) BOOL cancel;

@property (nonatomic, strong) id observerWillResignActive;
@property (nonatomic, strong) id observerWillActive;
@property (assign, nonatomic) BOOL isDeviceLocked;

@property (strong, nonatomic) QBChatMessage *attachmentMessage;
@property (strong, nonatomic) AttachmentUploadBar *attachmentBar;
@property (strong, nonatomic) ChatPrivateTitleView *chatPrivateTitleView;
@property (strong, nonatomic) UIBarButtonItem *infoItem;

@property (assign, nonatomic) NSUInteger inputToolBarStartPosition;
@property (assign, nonatomic) CGFloat collectionBottomConstant;

@property (strong, nonatomic) NSMutableSet *onlineUsersIDs;
@property (assign, nonatomic) Boolean isOpenPopVC;

@property (strong, nonatomic) MenuViewController *popVC;
@property (nonatomic, strong) SDImageCache *imageCache;

@end

@implementation ChatViewController

@synthesize pickerController = _pickerController;

- (UIImagePickerController *)pickerController {
    if (_pickerController == nil) {
        _pickerController = [UIImagePickerController new];
        _pickerController.delegate = self;
    }
    return _pickerController;
}

#pragma mark - Life Cycle
- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.dataSource = [[ChatDataSource alloc] init];
    self.dataSource.delegate = self;
    
    self.chatManager = [ChatManager instance];

    [self setupViewMessages];
    self.isDeviceLocked = NO;
    
    self.onlineUsersIDs = [NSMutableSet set];

    self.isOpenPopVC = NO;

    UIBarButtonItem *backButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"chevron"]
                                                                       style:UIBarButtonItemStylePlain
                                                                      target:self
                                                                      action:@selector(didTapBack:)];
    
    self.navigationItem.leftBarButtonItem = backButtonItem;
    backButtonItem.tintColor = UIColor.whiteColor;
    
    //Customize your toolbar buttons
    self.inputToolbar.contentView.leftBarButtonItem = [self accessoryButtonItem];
    self.inputToolbar.contentView.rightBarButtonItem = [self sendButtonItem];
    [self.inputToolbar setupBarButtonEnabledLeft:YES andRight:NO];
    
    self.systemInputToolbar = [[KVOView alloc] init];
    self.systemInputToolbar.collectionView = self.collectionView;
    self.systemInputToolbar.inputView = self.inputToolbar;
    self.systemInputToolbar.frame = CGRectMake(0, 0, 0, kSystemInputToolbarDebugHeight);
    __weak __typeof(self) weakSelf = self;
    self.systemInputToolbar.hostViewFrameChangeBlock = ^(UIView *view, BOOL animated) {
        CGFloat position = weakSelf.view.frame.size.height - [weakSelf.view.superview convertPoint:view.frame.origin toView:weakSelf.view].y;
        
        if (weakSelf.inputToolbar.contentView.textView.isFirstResponder) {
            if (view.superview.frame.origin.y > 0 && position <= 0) {
                return;
            }
        }
        
        const CGFloat startPosition = weakSelf.inputToolBarStartPosition;
        
        if (position < startPosition || !view) {
            position = startPosition;
        }
        
        [weakSelf setToolbarBottomConstraintValue:position animated:animated];
    };
    
    self.inputToolbar.contentView.textView.inputAccessoryView = self.systemInputToolbar;
    
    self.edgesForExtendedLayout = UIRectEdgeNone; //same UIRectEdgeNone
    self.isUploading = NO;
    self.cancel = NO;
    self.topContentAdditionalInset = 28.0f;
    self.inputToolBarStartPosition = 0;
    self.collectionBottomConstant = 0.0;
    
    self.imageCache = SDImageCache.sharedImageCache;
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    [self.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
    [self loadMessagesWithSkip:0];
    

    self.chatManager.delegate = self;
    self.chatManager.connectionDelegate = self;
    
    [QBChat.instance addDelegate: self];

    
    if (!QBSession.currentSession.currentUser) {
        return;
    }
    self.currentUser = QBSession.currentSession.currentUser;

    self.senderDisplayName = self.currentUser.fullName;
    self.senderID = self.currentUser.ID;
    
    [self setupTitleView];
    
    self.inputToolbar.delegate = self;
    if (self.inputToolbar.contentView.textView.isFirstResponder == NO) {
        self.toolbarBottomLayoutGuide.constant = (CGFloat)self.inputToolBarStartPosition;
    }
    
    [self updateCollectionViewInsets];
    self.collectionBottomConstraint.constant = self.collectionBottomConstant;
    
    if (self.dialog.type != QBChatDialogTypePublicGroup) {
        self.infoItem = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"moreInfo"]
                                                         style:UIBarButtonItemStylePlain
                                                        target:self
                                                        action:@selector(didTapInfo:)];
        
        self.navigationItem.rightBarButtonItem = self.infoItem;
        self.infoItem.tintColor = UIColor.whiteColor;
    }
    if (QBChat.instance.isConnected) {
        if (self.didAddUsers) {
            self.didAddUsers();
        }
    }
    
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    __weak __typeof(self)weakSelf = self;
    self.observerWillResignActive = [defaultCenter addObserverForName: UIApplicationWillResignActiveNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        __typeof(weakSelf)strongSelf = weakSelf;
        strongSelf.isDeviceLocked = YES;
    }];
    self.observerWillActive = [defaultCenter addObserverForName: UIApplicationDidBecomeActiveNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        __typeof(weakSelf)strongSelf = weakSelf;
        strongSelf.isDeviceLocked = NO;
        [strongSelf.collectionView reloadData];
    }];
    
    //request Online Users for group and public chats
    [self.dialog requestOnlineUsersWithCompletionBlock:^(NSMutableArray<NSNumber *> * _Nullable onlineUsers, NSError * _Nullable error) {
        if (onlineUsers) {
            for (NSNumber *userID in onlineUsers) {
                if (userID.unsignedIntValue != self.senderID) {
                    [self.onlineUsersIDs addObject:userID];
                }
            }
        } else if (error) {
            NSLog(@"requestOnlineUsers error %@", error.localizedDescription);
        }
    }];
    
    self.dialog.onJoinOccupant = ^(NSUInteger userID) {
        if (userID == self.senderID) {
            return;
        }
        [weakSelf.onlineUsersIDs addObject:@(userID)];
    };
    
    self.dialog.onLeaveOccupant = ^(NSUInteger userID) {
        if (userID == self.senderID) {
            return;
        }
        [weakSelf.onlineUsersIDs removeObject:@(userID)];
    };
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    
    [QBChat.instance removeDelegate:self];
    
    NSNotificationCenter *defaultCenter = [NSNotificationCenter defaultCenter];
    if (self.observerWillResignActive) {
        [defaultCenter removeObserver:(self.observerWillResignActive)];
    }
    if (self.observerWillActive) {
        [defaultCenter removeObserver:(self.observerWillActive)];
    }
    [defaultCenter removeObserver:(self)];
    // clearing typing status blocks
    [self.dialog clearTypingStatusBlocks];
}

#pragma mark - External Methods
- (void)sendAddOccupantsMessages:(NSArray<NSNumber *> *)selectedUsers action:(DialogActionType)action {
    [self setupTitleView];
    NSArray<NSNumber *> *usersIDs = action == DialogActionTypeAdd ? selectedUsers : self.dialog.occupantIDs;
    NSString *message = action == DialogActionTypeAdd ? [self systemMessageWithUsers:selectedUsers] : [self systemMessageWithChatName:self.dialog.name];
    
    __weak typeof(self)weakSelf = self;
    [self setDidAddUsers:^{
        __typeof(weakSelf)strongSelf = weakSelf;
        strongSelf.didAddUsers = nil;
        [ChatManager.instance sendAddingMessage:message
                                         action:action
                                      withUsers:usersIDs
                                       toDialog:strongSelf.dialog
                                     completion:^(NSError * _Nullable error, QBChatMessage * _Nonnull message) {
            if (error) {
                [strongSelf.dataSource addDraftMessage:message];
                // Autojoin to the group chat
                if (!strongSelf.dialog.isJoined) {
                    [strongSelf.dialog joinWithCompletionBlock:^(NSError *error) {
                        if (error) {
                            Log(@"[%@] dialog join error: %@",
                                NSStringFromClass([ChatViewController class]),
                                error.localizedDescription);
                        }
                    }];
                }
                [SVProgressHUD showErrorWithStatus:error.localizedDescription];
                return;
            }
            [strongSelf.dataSource addMessage:message];
        }];
    }];
}

- (NSString *)systemMessageWithChatName:(NSString *)chatName {
    NSString *message = [NSString stringWithFormat:@"%@ %@ \"%@\"", QBSession.currentSession.currentUser.fullName, @"created the group chat", chatName];
    return message;
}

- (NSString *)systemMessageWithUsers:(NSArray<NSNumber *> *)usersIDs {
    NSString *message = [NSString stringWithFormat:@"%@ %@ ", QBSession.currentSession.currentUser.fullName, @"added"];
    for (NSNumber *userID in usersIDs) {
        QBUUser *user = [self.chatManager.storage userWithID:userID.unsignedIntValue];
        message = [NSString stringWithFormat:@"%@%@,", message, user.name];
    }
    message = [message substringToIndex:message.length - 1];
    return message;
}

#pragma mark - Internal Methods

- (void)didTapBack:(UIButton *)sender {
    [self finishSendingMessageAnimated:NO];
    if (self.action == ChatActionChatFromCall && self.didOpenCallScreenWithSettings) {
        self.didOpenCallScreenWithSettings(nil);
    } else if (self.didCloseChatVC) {
        self.didCloseChatVC();
    }
}

- (void)cancelUploadFile {
    [self hideAttacnmentBar];
    self.isUploading = NO;
    __weak __typeof(self)weakSelf = self;
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:NSLocalizedString(@"SA_STR_ERROR", nil)
                                          message:NSLocalizedString(@"SA_STR_FAILED_UPLOAD_ATTACHMENT", nil)
                                          preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:NSLocalizedString(@"SA_STR_CANCEL", nil)
                                                           style:UIAlertActionStyleCancel handler:^(UIAlertAction * _Nonnull action) {
        [weakSelf.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
    }];
    [alertController addAction:cancelAction];
    
    [self presentViewController:alertController animated:NO completion:nil];
}

- (void)updateCollectionViewInsets {
    CGFloat topValue = 0.0f;
    CGFloat bottomValue = self.topContentAdditionalInset;
    
    [self setCollectionViewInsetsTopValue:topValue
                              bottomValue:bottomValue];
}

- (void)setCollectionViewInsetsTopValue:(CGFloat)top bottomValue:(CGFloat)bottom {
    UIEdgeInsets insets = UIEdgeInsetsZero;
    if (UIEdgeInsetsEqualToEdgeInsets(self.collectionView.contentInset, insets)) {
        return;
    }
    self.collectionView.contentInset = insets;
    self.collectionView.scrollIndicatorInsets = insets;
}

- (BOOL)isMenuVisible {
    //  check if cell copy menu is showing
    //  it is only our menu if `selectedIndexPathForMenu` is not `nil`
    return self.selectedIndexPathForMenu != nil && [[UIMenuController sharedMenuController] isMenuVisible];
}

#pragma mark - Setup
- (void)setupTitleView {
    self.title = self.dialog.name;
}

#pragma mark - Utility
- (NSString *)timeStampWithDate:(NSDate *)date {
    static NSDateFormatter *dateFormatter = nil;
    
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dateFormatter = [[NSDateFormatter alloc] init];
        dateFormatter.dateFormat = @"HH:mm";
    });
    
    NSString *timeStamp = [dateFormatter stringFromDate:date];
    
    return timeStamp;
}

#pragma mark - Input toolbar utilities
- (void)setToolbarBottomConstraintValue:(CGFloat)constraintValue animated:(BOOL)animated {
    
    if (constraintValue < 0) {
        return;
    }
    
    if (!animated) {
        
        CGFloat offset = self.collectionView.contentOffset.y +
        constraintValue - self.toolbarBottomLayoutGuide.constant;
        
        self.collectionView.contentOffset =
        CGPointMake(self.collectionView.contentOffset.x, offset);
    }
    
    self.toolbarBottomLayoutGuide.constant = constraintValue;
    
    if (animated) {
        [self.view layoutIfNeeded];
    }
}

- (void)loadMessagesWithSkip:(NSInteger)skip {
    [SVProgressHUD showWithStatus:NSLocalizedString(@"SA_STR_LOADING_MESSAGES", nil)];
    [self.chatManager messagesWithDialogID:self.dialog.ID
                           extendedRequest:nil
                                      skip:skip
                                   success:^(NSArray<QBChatMessage *> * _Nonnull messages, Boolean isLast) {
        self.cancel = isLast;
        [self.dataSource addMessages:messages];
        [SVProgressHUD dismiss];
    } errorHandler:^(NSString * _Nonnull error) {
        if (error == NSLocalizedString(@"SA_STR_DIALOG_REMOVED", nil)) {
            [self.dataSource clear];
            [self.dialog clearTypingStatusBlocks];
            self.inputToolbar.userInteractionEnabled = NO;
            self.collectionView.scrollEnabled = NO;
            [self.collectionView reloadData];
            self.title = @"";
            self.navigationItem.rightBarButtonItem.enabled = NO;
        }
        [SVProgressHUD dismiss];
    }];
}

- (void)setupViewMessages {
    [self registerCells];
    
    self.collectionView.transform = CGAffineTransformMake(1.0f, 0.0f, 0.0f, -1.0f, 0.0f, 0.0f);
    self.inputToolbar.contentView.textView.delegate = self;
    self.automaticallyScrollsToMostRecentMessage = YES;
}

- (void)registerCells {
    //Register header view
    UINib *headerNib = [HeaderCollectionReusableView nib];
    NSString *headerView = [HeaderCollectionReusableView cellReuseIdentifier];
    [self.collectionView registerNib:headerNib
          forSupplementaryViewOfKind:UICollectionElementKindSectionFooter
                 withReuseIdentifier:headerView];
    // Register cells
    [ChatNotificationCell registerForReuseInView:self.collectionView];
    [ChatOutgoingCell registerForReuseInView:self.collectionView];
    [ChatIncomingCell registerForReuseInView:self.collectionView];
    [ChatAttachmentIncomingCell registerForReuseInView:self.collectionView];
    [ChatAttachmentOutgoingCell registerForReuseInView:self.collectionView];
    [ChatDateCell registerForReuseInView:self.collectionView];
    [ChatCallOutgoingCell registerForReuseInView:self.collectionView];
    [ChatCallIncomingCell registerForReuseInView:self.collectionView];
}

#pragma mark - Tool bar
- (UIButton *)accessoryButtonItem {
    UIImage *accessoryImage = [ChatResources imageNamed:@"attachment_ic"];
    UIImage *normalImage = [accessoryImage imageMaskedWithColor:[UIColor mainColor]];
    UIImage *highlightedImage = [accessoryImage imageMaskedWithColor:[UIColor mainColor]];
    
    UIButton *accessoryButton =
    [[UIButton alloc] initWithFrame:CGRectMake(0.0f, 0.0f, accessoryImage.size.width, 32.0f)];
    [accessoryButton setImage:normalImage forState:UIControlStateNormal];
    [accessoryButton setImage:highlightedImage forState:UIControlStateHighlighted];
    
    accessoryButton.contentMode = UIViewContentModeScaleAspectFit;
    accessoryButton.backgroundColor = [UIColor clearColor];
    accessoryButton.tintColor = [UIColor mainColor];
    
    return accessoryButton;
}

- (UIButton *)sendButtonItem {
    UIImage *accessoryImage = [ChatResources imageNamed:@"send"];
    UIImage *normalImage = [accessoryImage imageMaskedWithColor:[UIColor mainColor]];
    UIImage *highlightedImage = [accessoryImage imageMaskedWithColor:[UIColor mainColor]];
    
    UIButton *sendButton =
    [[UIButton alloc] initWithFrame:CGRectMake(0.0f, 0.0f, accessoryImage.size.width, 28.0f)];
    [sendButton setImage:normalImage forState:UIControlStateNormal];
    [sendButton setImage:highlightedImage forState:UIControlStateHighlighted];
    
    sendButton.contentMode = UIViewContentModeScaleAspectFit;
    sendButton.backgroundColor = [UIColor clearColor];
    sendButton.tintColor = [UIColor mainColor];
    
    return sendButton;
}

- (void)startConference {
    if (!self.chatManager.onConnect) {
            [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
            [SVProgressHUD dismiss];
            return;
    }
    ConferenceInfo *conferenceInfo = [[ConferenceInfo alloc] initWithCallType:@"4" chatDialogID:self.dialog.ID conferenceID:self.dialog.ID initiatorID:@(self.senderID)];
    ConferenceSettings *callSettings = [[ConferenceSettings alloc] initWithConferenceInfo:conferenceInfo isSendMessage:YES];
    [self joinDialogWithCallSettings:callSettings];
}

- (void)joinConference:(ConferenceSettings *)settings {
    if (!self.chatManager.onConnect) {
            [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
            [SVProgressHUD dismiss];
            return;
    }
    if (self.action == ChatActionChatFromCall) {
        if (self.didOpenCallScreenWithSettings) {
            self.didOpenCallScreenWithSettings(settings);
        }
        return;
    }
    [self joinDialogWithCallSettings:settings];
}

- (void)startStreaming {
    if (!self.chatManager.onConnect) {
            [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
            [SVProgressHUD dismiss];
            return;
    }
    NSString *timeStampString = [NSString stringWithFormat:@"%lld", [@(floor([[NSDate date] timeIntervalSince1970] * 1000)) longLongValue]];
    NSString *streamID = [NSString stringWithFormat:@"%@_%@", @(self.senderID), timeStampString];
    ConferenceInfo *conferenceInfo = [[ConferenceInfo alloc] initWithCallType:@"5" chatDialogID:self.dialog.ID conferenceID:streamID initiatorID:@(self.senderID)];
    ConferenceSettings *callSettings = [[ConferenceSettings alloc] initWithConferenceInfo:conferenceInfo isSendMessage:YES];
    [self joinDialogWithCallSettings:callSettings];
}

- (void)joinStream:(ConferenceSettings *)settings {
    if (!self.chatManager.onConnect) {
            [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
            [SVProgressHUD dismiss];
            return;
    }
    if (self.action == ChatActionChatFromCall) {
        if (self.didOpenCallScreenWithSettings) {
            self.didOpenCallScreenWithSettings(settings);
        }
        return;
    }
    [self joinDialogWithCallSettings:settings];
}

- (void)joinDialogWithCallSettings:(ConferenceSettings *)callSettings {
    if (self.senderID != callSettings.conferenceInfo.initiatorID.unsignedIntValue && [callSettings.conferenceInfo.callType isEqualToString:@"5"]) {
        self.didOpenCallScreenWithSettings(callSettings);
    } else {
        [CallPermissions checkPermissionsWithConferenceType:QBRTCConferenceTypeVideo presentingViewController:self completion:^(BOOL granted) {
            if (!granted) {return;}
            self.didOpenCallScreenWithSettings(callSettings);
        }];
    }
}


- (void)didTapDelete {
    if (!self.chatManager.onConnect) {
            [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
            [SVProgressHUD dismiss];
            return;
    }
    UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"Warning" message:@"Do you really want to leave selected dialog?" preferredStyle:UIAlertControllerStyleAlert];

    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil];
    NSString *deleteMessage = @"Delete";
    if (self.dialog.type == QBChatDialogTypeGroup) {
        deleteMessage = @"Leave";
    }
    UIAlertAction *leaveAction = [UIAlertAction actionWithTitle:deleteMessage style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [SVProgressHUD showWithStatus:@"Leaving..."];
        self.infoItem.enabled = NO;
        if (self.dialog.type == QBChatDialogTypePublicGroup) {
            return;
        } else {
            // group
            self.dialog.pullOccupantsIDs = @[@(self.currentUser.ID).stringValue];

            NSString *message = [NSString stringWithFormat:@"%@ %@", self.currentUser.fullName, @"has left"];
            // Notifies occupants that user left the dialog.
            [self.chatManager sendLeaveMessage:message toDialog:self.dialog completion:^(NSError * _Nullable error) {
                if (error){
                    self.infoItem.enabled = YES;
                    Log(@"[%@] sendLeaveMessage error: %@",
                        NSStringFromClass([DialogsSelectionVC class]),
                        error.localizedDescription);
                    [SVProgressHUD dismiss];
                    return;
                }

                [self.chatManager leaveDialogWithID:self.dialog.ID completion:^(NSString * _Nullable error) {
                    if (self.didCloseChatVC) {
                        self.didCloseChatVC();
                    }
                }];
            }];
        }
    }];

    [alertController addAction:cancelAction];
    [alertController addAction:leaveAction];
    [self presentViewController:alertController animated:NO completion:nil];
}

- (void)didTapInfo:(UIBarButtonItem *)sender {
    UIStoryboard *storyboard = [UIStoryboard storyboardWithName:@"Chat" bundle:nil];
    MenuViewController *actionsMenuVC = [storyboard instantiateViewControllerWithIdentifier:@"MenuViewController"];
    actionsMenuVC.modalPresentationStyle = UIModalPresentationOverFullScreen;
    actionsMenuVC.menuType = TypeMenuChatInfo;

    __weak __typeof(self) weakSelf = self;
    
    MenuAction *chatInfoAction = [[MenuAction alloc] initWithTitle:@"Chat info" action:ChatActionChatInfo handler:^(ChatAction action) {
        __typeof(weakSelf)strongSelf = weakSelf;
        [strongSelf performSegueWithIdentifier:NSLocalizedString(@"SA_STR_SEGUE_GO_TO_INFO", nil) sender:@(ChatActionChatInfo)];
    }];
    
    if (self.action == ChatActionChatFromCall) {
        [actionsMenuVC addAction:chatInfoAction];
    } else {
        MenuAction *leaveChatAction = [[MenuAction alloc] initWithTitle:@"Leave Chat" action:ChatActionLeaveChat handler:^(ChatAction action) {
            __typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf didTapDelete];
        }];
        
        MenuAction *startStreamAction = [[MenuAction alloc] initWithTitle:@"Start Stream" action:ChatActionStartStream handler:^(ChatAction action) {
            __typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf startStreaming];
        }];
        
        MenuAction *startConferenceAction = [[MenuAction alloc] initWithTitle:@"Start Conference" action:ChatActionStartConference handler:^(ChatAction action) {
            __typeof(weakSelf)strongSelf = weakSelf;
            [strongSelf startConference];
        }];
        
        if (self.dialog.occupantIDs.count > 12) {
            [actionsMenuVC addAction:leaveChatAction];
            [actionsMenuVC addAction:chatInfoAction];
            [actionsMenuVC addAction:startStreamAction];
        } else {
            [actionsMenuVC addAction:leaveChatAction];
            [actionsMenuVC addAction:chatInfoAction];
            [actionsMenuVC addAction:startStreamAction];
            [actionsMenuVC addAction:startConferenceAction];   
        }
    }
    
    [actionsMenuVC setCancelAction:^{
        __typeof(weakSelf)strongSelf = weakSelf;
        [strongSelf hideKeyboard:NO];
    }];
    
    [self presentViewController:actionsMenuVC animated:NO completion:nil];
}

- (Class)viewClassForItem:(QBChatMessage *)item {
    NSString *notificationType = item.customParameters[@"notification_type"];
    
    if (notificationType) {
        if (item.customParameters[@"notification_type"].intValue == NotificationMessageTypeStartConference ||
            item.customParameters[@"notification_type"].intValue == NotificationMessageTypeStartStream) {
            if (item.senderID != self.senderID) {
                return [ChatCallIncomingCell class];
            } else {
                return [ChatCallOutgoingCell class];
            }
        }
        
        if (item.customParameters[@"notification_type"] != nil) {
            return [ChatNotificationCell class];
        }
    }
    
    if ( item.isDateDividerMessage) {
        return [ChatDateCell class];
    }
    
    if (item.senderID != self.senderID) {
        if (item.attachments.count > 0) {
            return [ChatAttachmentIncomingCell class];
        } else {
            return [ChatIncomingCell class];
        }
    } else {
        if (item.attachments.count > 0) {
            return [ChatAttachmentOutgoingCell class];
        } else {
            return [ChatOutgoingCell class];
        }
    }
}

#pragma mark - Strings builder
- (NSAttributedString *)attributedStringForItem:(QBChatMessage *)messageItem {
    if (!messageItem.text) {
        return [[NSAttributedString alloc] initWithString:@"@"];
    }
    
    UIColor *textColor = [messageItem senderID] == self.senderID ? [UIColor whiteColor] : [UIColor blackColor];
    if (messageItem.customParameters[@"notification_type"] != nil || messageItem.isDateDividerMessage) {
        textColor =  [UIColor blackColor];
    }
    
    UIFont *font = [UIFont fontWithName:@"Helvetica" size:15.0f] ;
    NSDictionary *attributes = @{ NSForegroundColorAttributeName:textColor,
                                  NSFontAttributeName:font};
    if (messageItem.customParameters[@"origin_sender_name"] != nil) {
        NSString *originForwardedName = messageItem.customParameters[@"origin_sender_name"];
        UIColor *forwardedColor = messageItem.senderID == self.senderID ? [UIColor.whiteColor colorWithAlphaComponent:0.6f] : [UIColor colorWithRed:0.41f green:0.48f blue:0.59f alpha:1.0f];
        UIFont *fontForwarded = [UIFont systemFontOfSize:13.0f weight:UIFontWeightLight];
        UIFont *fontForwardedName = [UIFont systemFontOfSize:13.0f weight:UIFontWeightSemibold];
        NSDictionary *attributesForwarded = @{ NSForegroundColorAttributeName: forwardedColor,
                                               NSFontAttributeName: fontForwarded};
        NSDictionary *attributesForwardedName = @{ NSForegroundColorAttributeName: forwardedColor,
                                                   NSFontAttributeName: fontForwardedName};
        NSMutableAttributedString *textForwarded = [[NSMutableAttributedString alloc] initWithString:@"Forwarded from " attributes: attributesForwarded];
        NSString *forwardedNameString = [NSString stringWithFormat:@"%@\n", originForwardedName];
        NSMutableAttributedString *forwardedName = [[NSMutableAttributedString alloc] initWithString:forwardedNameString attributes: attributesForwardedName];
        [textForwarded appendAttributedString:forwardedName];
        [textForwarded appendAttributedString:[[NSMutableAttributedString alloc] initWithString:messageItem.text
                                                                                     attributes:attributes]];
        return textForwarded;
    }
    
    return [[NSMutableAttributedString alloc] initWithString:messageItem.text
                                                  attributes:attributes];
}

- (NSAttributedString *)forwardedAttachmentAttributedString:(NSString *)originForwardedName {
    UIColor *forwardedColor = [UIColor colorWithRed:0.41f green:0.48f blue:0.59f alpha:1.0f];
    UIFont *fontForwarded = [UIFont systemFontOfSize:13.0f weight:UIFontWeightLight];
    UIFont *fontForwardedName = [UIFont systemFontOfSize:13.0f weight:UIFontWeightSemibold];
    NSDictionary *attributesForwarded = @{ NSForegroundColorAttributeName: forwardedColor,
                                           NSFontAttributeName: fontForwarded};
    NSDictionary *attributesForwardedName = @{ NSForegroundColorAttributeName: forwardedColor,
                                               NSFontAttributeName: fontForwardedName};
    NSMutableAttributedString *textForwarded = [[NSMutableAttributedString alloc] initWithString:@"Forwarded from " attributes: attributesForwarded];
    NSString *forwardedNameString = [NSString stringWithFormat:@"%@\n", originForwardedName];
    NSMutableAttributedString *forwardedName = [[NSMutableAttributedString alloc] initWithString:forwardedNameString attributes: attributesForwardedName];
    [textForwarded appendAttributedString:forwardedName];
    
    return textForwarded;
}

- (NSAttributedString *)topLabelAttributedStringForItem:(QBChatMessage *)messageItem {
    UIColor *textColor = [UIColor colorWithRed:0.43f green:0.48f blue:0.57f alpha:1.0f];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByClipping;
    UIFont *font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightSemibold];
    NSDictionary *attributes = @{ NSForegroundColorAttributeName:textColor,
                                  NSFontAttributeName:font,
                                  NSParagraphStyleAttributeName: paragraphStyle};
    NSString *topLabelString = @"";
    
    if ([messageItem senderID] == self.senderID) {
        topLabelString = @"You";
    } else {
        NSString *senderFullName = [self.chatManager.storage userWithID: messageItem.senderID].fullName;
        NSString *senderID = [NSString stringWithFormat:@"@%lu", (unsigned long)messageItem.senderID];
        topLabelString = senderFullName ? senderFullName : senderID;
    }
    
    return [[NSMutableAttributedString alloc] initWithString:topLabelString attributes:attributes];;
}

- (NSAttributedString *)timeLabelAttributedStringForItem:(QBChatMessage *)messageItem {
    UIColor *textColor = [UIColor colorWithRed:0.43f green:0.48f blue:0.57f alpha:1.0f];
    NSMutableParagraphStyle *paragraphStyle = [[NSMutableParagraphStyle alloc] init];
    paragraphStyle.lineBreakMode = NSLineBreakByWordWrapping;
    UIFont *font = [UIFont systemFontOfSize:13.0f weight:UIFontWeightRegular];
    NSDictionary *attributes = @{ NSForegroundColorAttributeName:textColor,
                                  NSFontAttributeName:font,
                                  NSParagraphStyleAttributeName: paragraphStyle};
    
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    formatter.dateFormat = formatter.dateFormat = @"HH:mm";
    NSString *text = [formatter stringFromDate:messageItem.dateSent];
    
    return [[NSMutableAttributedString alloc] initWithString:text
                                                  attributes:attributes];
}

#pragma mark - UIImagePickerController
- (void)imagePickerController:(UIImagePickerController *)picker
didFinishPickingMediaWithInfo:(NSDictionary<UIImagePickerControllerInfoKey, id> *)info {
    
    UIImage *image = info[UIImagePickerControllerOriginalImage];
    [self showAttachmentBarWith:image];
    
    [picker dismissViewControllerAnimated:YES completion:nil];
}

- (void)imagePickerControllerDidCancel:(UIImagePickerController *)picker {
    [picker dismissViewControllerAnimated:YES completion:nil];
}

#pragma mark - AttachmentBar
- (void)showAttachmentBarWith:(UIImage *)image {
    self.attachmentBar = [[NSBundle mainBundle] loadNibNamed:@"AttachmentUploadBar" owner:nil options:nil].firstObject;
    self.attachmentBar.delegate = self;
    [self.view addSubview:self.attachmentBar];
    
    self.attachmentBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.attachmentBar.leftAnchor constraintEqualToAnchor:self.inputToolbar.leftAnchor].active = YES;
    [self.attachmentBar.rightAnchor constraintEqualToAnchor:self.inputToolbar.rightAnchor].active = YES;
    [self.attachmentBar.bottomAnchor constraintEqualToAnchor:self.inputToolbar.topAnchor].active = YES;
    [self.attachmentBar.heightAnchor constraintEqualToConstant:attachmentBarHeight].active = YES;
    [self.attachmentBar uploadAttachmentImage:image pickerControllerSourceType:self.pickerController.sourceType];
    self.collectionBottomConstant = attachmentBarHeight;
    self.collectionBottomConstraint.constant = self.collectionBottomConstant;
    self.isUploading = YES;
    [self.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
}

- (void)hideAttacnmentBar {
    self.isUploading = NO;
    [self.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
    [self.attachmentBar removeFromSuperview];
    self.attachmentBar.attachmentImageView.image = nil;
    
    self.collectionBottomConstant = 0.0f;
    self.collectionBottomConstraint.constant = self.collectionBottomConstant;
    __weak typeof(self)weakSelf = self;
    [UIView animateWithDuration:0.03f animations:^{
        __typeof(weakSelf)strongSelf = weakSelf;
        [strongSelf.view layoutIfNeeded];
    }];
}

#pragma mark - AttachmentMessage
- (void)didPressSendButton:(UIButton *)button {
    if (!self.chatManager.onConnect) {
            [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
            [SVProgressHUD dismiss];
            return;
    }
    if (self.attachmentMessage) {
        [self hideAttacnmentBar];
        
        [self sendMessage:self.attachmentMessage];
    }
    
    if ([self currentlyComposedMessageText].length) {
        QBChatMessage *message = [[QBChatMessage alloc] init];
        message.text = [self currentlyComposedMessageText];
        message.senderID = self.senderID;
        message.deliveredIDs = @[@(self.senderID)];
        message.readIDs = @[@(self.senderID)];
        message.markable = YES;
        message.dateSent = [NSDate date];
        message.customParameters[@"save_to_history"] = @"1";
        
        [self sendMessage:message];
    }
}

- (void)sendMessage:(QBChatMessage *)message {
    __weak typeof(self)weakSelf = self;
    
    [self.chatManager sendMessage:message toDialog:self.dialog completion:^(NSError * _Nullable error) {
        __typeof(weakSelf)strongSelf = weakSelf;
        if (error) {
            // Autojoin to the group chat
            [SVProgressHUD showErrorWithStatus: @"Chat is not connected"];
            if (!self.dialog.isJoined) {
                [self.dialog joinWithCompletionBlock:^(NSError *error) {
                    if (error) {
                        Log(@"[%@] dialog join error: %@",
                            NSStringFromClass([ChatViewController class]),
                            error.localizedDescription);
                    }
                }];
            }
            Log(@"%@ sendMessage error: %@",NSStringFromClass([ChatViewController class]),
                error.localizedDescription);
            return;
        }
        [strongSelf.dataSource addMessage:message];
        [strongSelf finishSendingMessageAnimated:YES];
    }];
}

- (QBChatMessage *)createAttachmentMessageWith:(QBChatAttachment *)attachment {
    QBChatMessage *message = [QBChatMessage new];
    message.senderID = self.senderID;
    message.dialogID = self.dialog.ID;
    message.dateSent = [NSDate date];
    message.text = @"[Attachment]";
    message.deliveredIDs = @[@(self.senderID)];
    message.readIDs = @[@(self.senderID)];
    message.customParameters[@"save_to_history"] = @"1";
    message.attachments = @[attachment];
    message.markable = YES;
    return message;
}

- (void)finishSendingMessageAnimated:(BOOL)animated {
    PlaceHolderTextView *textView = self.inputToolbar.contentView.textView;
    [textView setDefaultSettings];
    
    textView.text = nil;
    textView.attributedText = nil;
    textView.placeHolder = @"Send message";
    [textView.undoManager removeAllActions];
    
    if (self.attachmentMessage) {
        self.attachmentMessage = nil;
    }
    
    [[NSNotificationCenter defaultCenter] postNotificationName:UITextViewTextDidChangeNotification object:textView];
    
    if (self.automaticallyScrollsToMostRecentMessage) {
        [self scrollToBottomAnimated:animated];
    }
}

- (void)finishReceivingMessageAnimated:(BOOL)animated {
    if (self.automaticallyScrollsToMostRecentMessage && ![self isMenuVisible]) {
        [self scrollToBottomAnimated:animated];
    }
}

- (void)scrollToBottomAnimated:(BOOL)animated {
    if ([self.collectionView numberOfItemsInSection:0] == 0) {
        return;
    }
    
    CGPoint contentOffset = self.collectionView.contentOffset;
    if (contentOffset.y > 0.0f) {
        contentOffset.y = 0.0f;
        [self.collectionView setContentOffset:contentOffset
                                     animated:animated];
    }
}

#pragma mark - UIScrollViewDelegate
- (BOOL)scrollViewShouldScrollToTop:(UIScrollView *)scrollView {
    // disabling scroll to bottom when tapping status bar
    return NO;
}

- (CGRect)scrollTopRect {
    return CGRectMake(0.0,
                      self.collectionView.contentSize.height - CGRectGetHeight(self.collectionView.bounds),
                      CGRectGetWidth(self.collectionView.bounds),
                      CGRectGetHeight(self.collectionView.bounds));
}

- (void)hideKeyboard:(BOOL)animated {
    dispatch_block_t hideKeyboardBlock = ^{
        if (self.inputToolbar.contentView.textView.isFirstResponder) {
            [self.inputToolbar.contentView resignFirstResponder];
        }
    };
    
    if (!animated) {
        [UIView performWithoutAnimation:hideKeyboardBlock];
    } else {
        hideKeyboardBlock();
    }
}

- (void)didPressAccessoryButton:(UIButton *)sender {
    if (self.isUploading) {
        [self showAlertWithTitle:@"You can send 1 attachment per message" message:nil
              fromViewController:self];
    } else {
        UIAlertController *alertController = [UIAlertController
                                              alertControllerWithTitle:nil
                                              message:nil
                                              preferredStyle:UIAlertControllerStyleActionSheet];
        
        __weak __typeof(self) weakSelf = self;
        
        void(^handlerWithSourceType)(UIImagePickerControllerSourceType sourceType) = ^(UIImagePickerControllerSourceType sourceType){
            [self checkAuthorizationStatusWithSourceType:sourceType completion:^(BOOL granted) {
                typeof(weakSelf) strongSelf = weakSelf;
                
                if (granted) {
                    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
                        [strongSelf presentViewController:self.pickerController
                                                 animated:YES
                                               completion:nil];
                        
                    } else if (sourceType == UIImagePickerControllerSourceTypePhotoLibrary) {
                        [strongSelf showAllAssets];
                    }
                } else {
                    [strongSelf showAlertForAccess];
                }
            }];
        };
        
        
#if TARGET_OS_SIMULATOR
        NSLog(@"targetEnvironment simulator");
#else
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Camera", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull __unused action) {
            weakSelf.pickerController.sourceType = UIImagePickerControllerSourceTypeCamera;
            handlerWithSourceType(UIImagePickerControllerSourceTypeCamera);
        }]];
#endif
        
        
        
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Photo", nil)
                                                            style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * _Nonnull __unused action) {
            weakSelf.pickerController.sourceType = UIImagePickerControllerSourceTypePhotoLibrary;
            handlerWithSourceType(UIImagePickerControllerSourceTypePhotoLibrary);
        }]];
        
        [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                            style:UIAlertActionStyleCancel
                                                          handler:nil]];
        
        if (alertController.popoverPresentationController) {
            // iPad support
            alertController.popoverPresentationController.sourceView = sender;
            alertController.popoverPresentationController.sourceRect = sender.bounds;
        }
        [self presentViewController:alertController animated:YES completion:NULL];
    }
}

- (void)showAllAssets {
    SelectAssetsVC *selectAssetsVC = [self.storyboard instantiateViewControllerWithIdentifier:@"SelectAssetsVC"];
    selectAssetsVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    __weak __typeof(self) weakSelf = self;
    selectAssetsVC.selectedImage = ^(UIImage *image) {
        if (image) {
            [weakSelf showAttachmentBarWith:image];
        }
    };
    [self presentViewController:selectAssetsVC animated:NO completion:nil];
}

- (void)checkAuthorizationStatusWithSourceType:(UIImagePickerControllerSourceType)sourceType completion:(void (^)(BOOL granted))completion {
    BOOL granted = NO;
    
    if (sourceType == UIImagePickerControllerSourceTypeCamera) {
        AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
        switch (status) {
            case AVAuthorizationStatusNotDetermined: {
                [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                                         completionHandler:^(BOOL granted) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) {
                            completion(granted);
                        }
                    });
                }];
                return;
            }
            case AVAuthorizationStatusRestricted:
            case AVAuthorizationStatusDenied:
                break;
            case AVAuthorizationStatusAuthorized: {
                granted = YES;
                break;
            }
        }
    } else if (sourceType == UIImagePickerControllerSourceTypePhotoLibrary) {
        PHAuthorizationStatus status = [PHPhotoLibrary authorizationStatus];
        switch (status) {
            case PHAuthorizationStatusAuthorized: {
                granted = YES;
                break;
            }
            case PHAuthorizationStatusNotDetermined: {
                [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus authorizationStatus) {
                    dispatch_async(dispatch_get_main_queue(), ^{
                        if (completion) {
                            completion(authorizationStatus == PHAuthorizationStatusAuthorized);
                        }
                    });
                }];
                return;
            }
            default: break;
        }
    }
    
    if (completion) {
        completion(granted);
    }
}

- (void)showAlertForAccess {
    
    NSString *title = @"";
    NSString *message = @"";
    
    if (self.pickerController.sourceType == UIImagePickerControllerSourceTypeCamera) {
        title = NSLocalizedString(@"Camera Access Disabled", nil);
        message = NSLocalizedString(@"You can allow access to Camera in Settings", nil);
    }
    else if (self.pickerController.sourceType == UIImagePickerControllerSourceTypePhotoLibrary) {
        title = NSLocalizedString(@"Photos Access Disabled", nil);
        message = NSLocalizedString(@"You can allow access to Photos in Settings", nil);
    }
    
    UIAlertController *alertController = [UIAlertController
                                          alertControllerWithTitle:title
                                          message:message
                                          preferredStyle:UIAlertControllerStyleAlert];
    
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Open Settings", nil)
                                                        style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * _Nonnull __unused action)
                                {
        [[UIApplication sharedApplication]
         openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString]
         options:@{}
         completionHandler:nil];
    }]];
    
    [alertController addAction:[UIAlertAction actionWithTitle:NSLocalizedString(@"Cancel", nil)
                                                        style:UIAlertActionStyleCancel
                                                      handler:nil]];
    
    [self presentViewController:alertController animated:YES completion:nil];
}

- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
    
    [coordinator animateAlongsideTransition:nil
                                 completion:^(id<UIViewControllerTransitionCoordinatorContext>  _Nonnull context) {
        [self updateCollectionViewInsets];
    }];
    
    if (self.inputToolbar.contentView.textView.isFirstResponder && self.splitViewController) {
        if(!self.splitViewController.isCollapsed) {
            [self.inputToolbar.contentView.textView resignFirstResponder];
        }
    }
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
}

- (BOOL)scrollIsAtTop {
    return CGRectGetMaxY([self scrollVisibleRect]) >= CGRectGetMaxY([self scrollTopRect]);
}

- (CGRect)scrollVisibleRect {
    CGRect visibleRect = CGRectZero;
    visibleRect.origin = self.collectionView.contentOffset;
    visibleRect.size = self.collectionView.frame.size;
    return visibleRect;
}

- (void)prepareForSegue:(UIStoryboardSegue *)segue sender:(id)sender {
    if ([segue.identifier isEqualToString:NSLocalizedString(@"SA_STR_SEGUE_GO_TO_INFO", nil)]) {
        UsersInfoTableViewController *usersInfoViewController = segue.destinationViewController;
        usersInfoViewController.dialogID = self.dialog.ID;
        ChatAction action = (ChatAction)([sender unsignedIntValue]);
        usersInfoViewController.action = action;
        if (self.selectedIndexPathForMenu) {
            QBChatMessage *message = [self.dataSource messageWithIndexPath:self.selectedIndexPathForMenu];
            if (message) {
                usersInfoViewController.message = message;
                if (action) {
                    usersInfoViewController.dataSource = self.dataSource;
                }
            }
        }
        
    }
}

#pragma mark - ChatDataSourceDelegate
- (void)chatDataSource:(ChatDataSource *)chatDataSource willBeChangedWithMessageIDs:(NSArray *)messagesIDs {
    for (NSString *messageID in messagesIDs) {
        [self.collectionView.collectionViewLayout removeSizeFromCacheForItemID:messageID];
    }
}

- (void)chatDataSource:(ChatDataSource *)dataSource
    changeWithMessages:(NSArray *)messages
                action:(DataSourceActionType)action {
    if (messages.count == 0 ) {
        return;
    }
    
    dispatch_block_t batchUpdatesBlock = ^{
        NSArray *indexPaths = [self.dataSource performChangesWithMessages:messages updateType:action];
        switch (action) {
            case DataSourceActionTypeAdd:
                [self.collectionView insertItemsAtIndexPaths:indexPaths];
                break;
            case DataSourceActionTypeUpdate:
                [self.collectionView reloadItemsAtIndexPaths:indexPaths];
                break;
            case DataSourceActionTypeRemove:
                [self.collectionView deleteItemsAtIndexPaths:indexPaths];
                break;
        }
    };
    
    [self.collectionView performBatchUpdates:batchUpdatesBlock completion:nil];
}

#pragma mark - Input toolbar delegate
- (void)messagesInputToolbar:(InputToolbar *)toolbar didPressLeftBarButton:(UIButton *)sender {
    if (toolbar.sendButtonOnRight) {
        [self didPressAccessoryButton:sender];
    } else {
        [self didPressSendButton:sender];
    }
}

- (void)messagesInputToolbar:(InputToolbar *)toolbar didPressRightBarButton:(UIButton *)sender {
    if (toolbar.sendButtonOnRight) {
        [self didPressSendButton:sender];
    } else {
        [self didPressAccessoryButton:sender];
    }
}

- (NSString *)currentlyComposedMessageText {
    //  auto-accept any auto-correct suggestions
    [self.inputToolbar.contentView.textView.inputDelegate selectionWillChange:self.inputToolbar.contentView.textView];
    [self.inputToolbar.contentView.textView.inputDelegate selectionDidChange:self.inputToolbar.contentView.textView];
    
    return [self.inputToolbar.contentView.textView.text stringByTrimingWhitespace];
}

#pragma mark - Collection view data source
- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return [self.dataSource messagesCount];
}

- (UICollectionViewCell *)collectionView:(ChatCollectionView *)collectionView
                  cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    
    QBChatMessage *messageItem = [self.dataSource messageWithIndexPath:indexPath];
    
    Class class = [self viewClassForItem:messageItem];
    NSString *itemIdentifier = [class cellReuseIdentifier];
    
    ChatCell *cell =
    [collectionView dequeueReusableCellWithReuseIdentifier:itemIdentifier
                                              forIndexPath:indexPath];
    
    [self collectionView:collectionView configureCell:cell forIndexPath:indexPath];
    
    NSInteger lastSection = collectionView.numberOfSections - 1;
    BOOL isLastItem = indexPath.item == [collectionView numberOfItemsInSection:lastSection] - 1;
    if (isLastItem && self.cancel == NO)  {
        [self loadMessagesWithSkip: [self.dataSource loadMessagesCount]];
    }
    
    return cell;
}

- (void)collectionView:(ChatCollectionView *)collectionView
         configureCell:(UICollectionViewCell *)cell
          forIndexPath:(NSIndexPath *)indexPath {
    
    QBChatMessage *message = [self.dataSource messageWithIndexPath:indexPath];
    
    if (message.senderID != self.senderID && ![message.readIDs containsObject:@(self.senderID)]) {
        if (![QBChat.instance isConnected]) {
            [self.dataSource addMessageForRead:message];
        } else {
            [self.chatManager readMessage:message dialog:self.dialog completion:^(NSError * _Nullable error) {
                if (!error) {
                    NSMutableArray *readIDs = [message.readIDs mutableCopy];
                    [readIDs addObject:@(self.senderID)];
                    [message setReadIDs: [readIDs copy]];
                    [self.dataSource updateMessage:message];
                    [self.dataSource removeMessageForRead:message];
                }
            }];
        }
    }
    
    if ([cell isKindOfClass:[ChatDateCell class]])  {
        ChatDateCell *dateCell = (ChatDateCell *)cell;
        dateCell.userInteractionEnabled = NO;
        dateCell.dateLabel.text = [[self attributedStringForItem:message] string];
        return;
    }
    
    if ([cell isKindOfClass:[ChatNotificationCell class]]) {
        [(ChatNotificationCell *)cell notificationLabel].text = [self attributedStringForItem:message].string;
        cell.userInteractionEnabled = NO;
        return;
    }
    
    if ([cell isKindOfClass:[ChatCallIncomingCell class]]) {
        ChatCallIncomingCell *callCell = (ChatCallIncomingCell *)cell;
        callCell.streamLabel.text = [self attributedStringForItem:message].string;
        NSAttributedString *userNameAttributedString = [self topLabelAttributedStringForItem:message];
        NSString *userName = userNameAttributedString.string;
        NSCharacterSet *characterSet = [NSCharacterSet whitespaceCharacterSet];
        NSString *name = [userName stringByTrimmingCharactersInSet:characterSet];
        NSString *firstLetter = [name substringToIndex:1];
        callCell.avatarLabel.text = [firstLetter uppercaseString];
        callCell.avatarLabel.backgroundColor = [UIColor colorWithHexString:[NSString stringWithFormat:@"#%lX",
                                                                            (unsigned long)message.senderID]];
        callCell.topLabel.text = name;
        callCell.timeLabel.text = [self timeLabelAttributedStringForItem:message];
        
        NSString *callType = message.customParameters[@"notification_type"];
        NSString *conferenceID = message.customParameters[@"conference_id"];
        if (!callType || !conferenceID) {
            return;
        }

        __weak typeof(self)weakSelf = self;
        [callCell setDidPressJoinButton:^{
            __typeof(weakSelf)strongSelf = weakSelf;
            ConferenceInfo *conferenceInfo = [[ConferenceInfo alloc] initWithCallType:callType chatDialogID:strongSelf.dialog.ID conferenceID:conferenceID initiatorID:@(message.senderID)];
            ConferenceSettings *callSettings = [[ConferenceSettings alloc] initWithConferenceInfo:conferenceInfo isSendMessage:NO];
            if (callType.intValue == NotificationMessageTypeStartConference) {
                [strongSelf joinConference:callSettings];
            } else {
                [strongSelf joinStream:callSettings];
            }
        }];
        return;
    }
    
    if ([cell isKindOfClass:[ChatCallOutgoingCell class]]) {
        ChatCallOutgoingCell *callCell = (ChatCallOutgoingCell *)cell;
        callCell.streamLabel.text = [self attributedStringForItem:message].string;
        callCell.timeLabel.text = [self timeLabelAttributedStringForItem:message];
        
        NSString *callType = message.customParameters[@"notification_type"];
        NSString *conferenceID = message.customParameters[@"conference_id"];
        if (!callType || !conferenceID) {
            return;
        }

        __weak typeof(self)weakSelf = self;
        [callCell setDidPressJoinButton:^{
            __typeof(weakSelf)strongSelf = weakSelf;
            ConferenceInfo *conferenceInfo = [[ConferenceInfo alloc] initWithCallType:callType chatDialogID:strongSelf.dialog.ID conferenceID:conferenceID initiatorID:@(message.senderID)];
            ConferenceSettings *callSettings = [[ConferenceSettings alloc] initWithConferenceInfo:conferenceInfo isSendMessage:NO];
            if (callType.intValue == NotificationMessageTypeStartConference) {
                [strongSelf joinConference:callSettings];
            } else {
                [strongSelf joinStream:callSettings];
            }
        }];
        return;
    }

    if ([cell isKindOfClass:[ChatCell class]]) {
        ChatCell *chatCell = (ChatCell *)cell;
        
        NSAttributedString *userNameAttributedString = [self topLabelAttributedStringForItem:message];
        NSString *userName = userNameAttributedString.string;
        NSCharacterSet *characterSet = [NSCharacterSet whitespaceCharacterSet];
        NSString *name = [userName stringByTrimmingCharactersInSet:characterSet];
        if ([cell isKindOfClass:[ChatIncomingCell class]] || [cell isKindOfClass:[ChatOutgoingCell class]]) {
            chatCell.textView.enabledTextCheckingTypes = self.enableTextCheckingTypes;
        }
        if ([cell isKindOfClass:[ChatIncomingCell class]]) {
            NSString *firstLetter = [name substringToIndex:1];
            chatCell.avatarLabel.text = [firstLetter uppercaseString];
            chatCell.avatarLabel.backgroundColor = [UIColor colorWithHexString:[NSString stringWithFormat:@"#%lX",
                                                                                (unsigned long)message.senderID]];
        }
        chatCell.topLabel.text = name;
        chatCell.timeLabel.text = [self timeLabelAttributedStringForItem:message];

        if (chatCell.textView ) {
            chatCell.textView.text = [self attributedStringForItem:message];
        }
        
        chatCell.delegate = self;
    }
    
    if ([cell isKindOfClass:[ChatAttachmentCell class]]) {
        ChatAttachmentCell *attachmentCell = (ChatAttachmentCell *)cell;
        cell.userInteractionEnabled = YES;
        QBChatAttachment *attachment = message.attachments.firstObject;
        NSString *attachmentID = attachment.ID;
        
        if ([attachmentCell isKindOfClass:[ChatAttachmentIncomingCell class]]) {
            ChatAttachmentIncomingCell *attachmentIncomingCell  = (ChatAttachmentIncomingCell *)cell;
            NSAttributedString *userNameAttributedString = [self topLabelAttributedStringForItem:message];
            NSString *userName = userNameAttributedString.string;
            NSCharacterSet *characterSet = [NSCharacterSet whitespaceCharacterSet];
            NSString *name = [userName stringByTrimmingCharactersInSet:characterSet];
            NSString *firstLetter = [name substringToIndex:1];
            attachmentIncomingCell.avatarLabel.text = [firstLetter uppercaseString];
            attachmentIncomingCell.avatarLabel.backgroundColor = [UIColor colorWithHexString:[NSString stringWithFormat:@"#%lX",
                                                                                              (unsigned long)message.senderID]];
        }
        NSString *originForwardName = message.customParameters[@"origin_sender_name"];
        if (originForwardName) {
            attachmentCell.forwardInfoHeightConstraint.constant = 35.0f;
            attachmentCell.forwardedLabel.attributedText = [self forwardedAttachmentAttributedString:originForwardName];
        } else {
            attachmentCell.forwardInfoHeightConstraint.constant = 0.0f;
        }

        if ([attachment.type isEqualToString:@"image"]) {
            attachmentCell.bottomInfoHeightConstraint.constant = 0.0f;
            attachmentCell.typeAttachmentImageView.image = [UIImage imageNamed:@"image_attachment"];
            [attachmentCell setupAttachment:attachment attachmentType:AttachmentTypeImage completion:nil];
            
        } else if ([attachment.type isEqualToString:@"video"]) {
            attachmentCell.bottomInfoHeightConstraint.constant = 60.0f;
            attachmentCell.playImageView.hidden = NO;
            attachmentCell.attachmentNameLabel.text = attachment.name;
            if (attachment.customParameters[@"size"]) {
                NSString *size = attachment.customParameters[@"size"];
                double sizeMB = [size doubleValue];
                attachmentCell.attachmentSizeLabel.text = [NSString stringWithFormat:@"%.02f MB", sizeMB/1048576];
            }
            NSString *appendingPathComponent = [NSString stringWithFormat:@"%@_%@", attachmentID, attachment.name];
            NSString *path = [NSString stringWithFormat:@"%@/%@", CacheManager.instance.cachesDirectory, appendingPathComponent];
            NSURL *videoURL = [NSURL fileURLWithPath:path];
            
            if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
                attachmentCell.attachmentUrl = videoURL;
                if ([self.imageCache imageFromCacheForKey:attachmentID]) {
                    UIImage *image = [self.imageCache imageFromCacheForKey:attachmentID];
                    attachmentCell.attachmentImageView.image = image;
                } else {
                    [videoURL getThumbnailImageFromVideoUrlWithCompletion:^(UIImage * _Nullable thumbnailImage) {
                        if (thumbnailImage) {
                            attachmentCell.attachmentImageView.image = thumbnailImage;
                            [self.imageCache storeImage:thumbnailImage forKey:attachmentID toDisk:NO completion:^{
                            }];
                        }
                    }];
                }
            } else {
                attachmentCell.typeAttachmentImageView.image = [UIImage imageNamed:@"video_attachment"];
                [attachmentCell setupAttachment:attachment attachmentType:AttachmentTypeVideo completion:^(NSURL * _Nonnull videoURl) {
                    if (videoURL) {
                        attachmentCell.attachmentUrl = videoURL;
                    }
                }];
            }
        } else if ([attachment.type isEqualToString:@"file"]) {
            attachmentCell.attachmentNameLabel.text = attachment.name;
            attachmentCell.bottomInfoHeightConstraint.constant = 60.0f;
            attachmentCell.attachmentImageView.backgroundColor = UIColor.whiteColor;
            attachmentCell.infoTopLineView.backgroundColor = [UIColor colorWithRed:0.85f green:0.89f blue:0.97f alpha:1.0f];
            attachmentCell.typeAttachmentImageView.image = [UIImage imageNamed:@"file"];
            if (attachment.customParameters[@"size"]) {
                NSString *size = attachment.customParameters[@"size"];
                double sizeMB = [size doubleValue];
                attachmentCell.attachmentSizeLabel.text = [NSString stringWithFormat:@"%.02f MB", sizeMB/1048576];
            }
            NSString *appendingPathComponent = [NSString stringWithFormat:@"%@_%@", attachmentID, attachment.name];
            NSString *path = [NSString stringWithFormat:@"%@/%@", CacheManager.instance.cachesDirectory, appendingPathComponent];
            NSURL *fileURL = [NSURL fileURLWithPath:path];
            
            if ([NSFileManager.defaultManager fileExistsAtPath:path]) {
                attachmentCell.attachmentUrl = fileURL;
                if ([self.imageCache imageFromCacheForKey:attachmentID]) {
                    UIImage *image = [self.imageCache imageFromCacheForKey:attachmentID];
                    attachmentCell.attachmentImageView.image = image;
                    attachmentCell.typeAttachmentImageView.image = nil;
                    attachmentCell.attachmentImageView.contentMode = UIViewContentModeScaleAspectFit;
                } else {
                    if ([attachment.name hasSuffix:@"pdf"]) {
                        [fileURL imageFromPDFfromURLWithCompletion:^(UIImage * _Nullable thumbnailImage) {
                            if (thumbnailImage) {
                                attachmentCell.attachmentImageView.image = thumbnailImage;
                                attachmentCell.typeAttachmentImageView.image = nil;
                                attachmentCell.attachmentImageView.contentMode = UIViewContentModeScaleAspectFit;
                                [self.imageCache storeImage:thumbnailImage forKey:attachmentID toDisk:NO completion:^{
                                }];
                            }
                        }];
                    }
                }
            } else {
                [attachmentCell setupAttachment:attachment attachmentType:AttachmentTypeVideo completion:^(NSURL * _Nonnull fileURL) {
                    if (fileURL) {
                        attachmentCell.attachmentUrl = fileURL;
                    }
                }];
            }
        }
    }
}

- (void)collectionView:(ChatCollectionView *)collectionView
       willDisplayCell:(nonnull UICollectionViewCell *)cell
    forItemAtIndexPath:(nonnull NSIndexPath *)indexPath {
    
    if (self.isDeviceLocked) {
        return;
    }
    
    QBChatMessage *message = [self.dataSource messageWithIndexPath:indexPath];
    if (self.isDeviceLocked) {
        return;
    }

    if ((![cell isKindOfClass:[ChatIncomingCell class]]
         || ![cell isKindOfClass:[ChatAttachmentIncomingCell class]])) {
        return;
    }
    
    if ([self.chatManager.storage userWithID:message.senderID]) {
        return;
    }
    
    [self.chatManager loadUserWithID:message.senderID completion:^(QBUUser * _Nullable user) {
        ChatCell *chatCell = (ChatCell *)cell;
        if ([cell isKindOfClass:[ChatIncomingCell class]]) {
            chatCell.textView.enabledTextCheckingTypes = self.enableTextCheckingTypes;
        }
        NSAttributedString *userNameAttributedString = [self topLabelAttributedStringForItem:message];
        NSString *userName = userNameAttributedString.string;
        NSCharacterSet *characterSet = [NSCharacterSet whitespaceCharacterSet];
        NSString *name = [userName stringByTrimmingCharactersInSet:characterSet];
        chatCell.avatarLabel.text = name.firstLetter;
        chatCell.avatarLabel.backgroundColor = [UIColor colorWithHexString:[NSString stringWithFormat:@"#%lX",
                                                                            (unsigned long)message.senderID]];
        chatCell.topLabel.text = name;
    }];
}

- (void)collectionView:(ChatCollectionView *)collectionView
  didEndDisplayingCell:(nonnull UICollectionViewCell *)cell
    forItemAtIndexPath:(nonnull NSIndexPath *)indexPath {
    if ([cell isKindOfClass:[ChatAttachmentCell class]]) {
        QBChatMessage *item = [self.dataSource messageWithIndexPath:indexPath];
        if (!item) {
            return;
        }
        QBChatAttachment *attachment = item.attachments.firstObject;
        if (!attachment) {
            return;
        }
        NSString *attachmentID = attachment.ID;
        AttachmentDownloadManager *attachmentDownloadManager = [[AttachmentDownloadManager alloc] init];
        [attachmentDownloadManager slowDownloadAttachmentWithID:attachmentID];
    }
}

#pragma mark - Collection view delegate flow layout
- (CGSize)collectionView:(ChatCollectionView *)collectionView
                  layout:(ChatCollectionViewFlowLayout *)collectionViewLayout
  sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    return [collectionViewLayout sizeForItemAtIndexPath:indexPath];
}

- (ChatCellLayoutModel)collectionView:(ChatCollectionView *)collectionView
               layoutModelAtIndexPath:(NSIndexPath *)indexPath {
    QBChatMessage *item = [self.dataSource messageWithIndexPath:indexPath];
    Class cellClass = [self viewClassForItem:item];
    ChatCellLayoutModel layoutModel = [cellClass layoutModel];
    
    layoutModel.avatarSize = CGSizeZero;
    layoutModel.maxWidthMarginSpace = 20.0f;
    
    if (cellClass == ChatIncomingCell.self || cellClass == ChatAttachmentIncomingCell.self || cellClass == ChatCallIncomingCell.self) {
        layoutModel.avatarSize = CGSizeMake(40.0f, 40.0f);
    }
    
    layoutModel.spaceBetweenTopLabelAndTextView = 12.0f;
    
    return layoutModel;
}

- (CGFloat)collectionView:(ChatCollectionView *)collectionView minWidthAtIndexPath:(NSIndexPath *)indexPath {
    
    QBChatMessage *item = [self.dataSource messageWithIndexPath:indexPath];
    
    CGFloat frameWidth = self.collectionView.frame.size.width;
    CGSize constraintsSize = CGSizeMake(frameWidth - widthPadding, CGFLOAT_MAX);
    
    NSAttributedString *dateAttributedString = [self timeLabelAttributedStringForItem:item];
    
    CGSize sizeDateAttributedString = [TTTAttributedLabel sizeThatFitsAttributedString:dateAttributedString
                                                                       withConstraints:constraintsSize
                                                                limitedToNumberOfLines:1];
    NSAttributedString *nameAttributedString = [self topLabelAttributedStringForItem:item];
    CGSize topLabelSize = [TTTAttributedLabel sizeThatFitsAttributedString:nameAttributedString
                                                           withConstraints:constraintsSize
                                                    limitedToNumberOfLines:1];
    
    Class cellClass = [self viewClassForItem:item];
    if (cellClass == ChatCallIncomingCell.self) {
        return 200.0f;
    }
    if (cellClass == ChatCallOutgoingCell.self) {
        return 220.0f;
    }
    
    if (item.senderID == self.senderID) {
        CGFloat statusWidth = 46.0f;
        return topLabelSize.width + sizeDateAttributedString.width + statusWidth;
    }

    CGFloat topLabelWidth = topLabelSize.width + sizeDateAttributedString.width + 6.0f;
    
    return topLabelWidth > 86.0f ? topLabelWidth : 86.0f;
}

- (CGSize)collectionView:(ChatCollectionView *)collectionView
  dynamicSizeAtIndexPath:(NSIndexPath *)indexPath
                maxWidth:(CGFloat)maxWidth {
    QBChatMessage *item = [self.dataSource messageWithIndexPath:indexPath];
    Class viewClass = [self viewClassForItem:item];
    
    CGSize size = CGSizeZero;
    NSAttributedString *attributedString = [self attributedStringForItem:item];
    if (viewClass == [ChatAttachmentIncomingCell class] || viewClass == [ChatAttachmentOutgoingCell class]) {
        size = CGSizeMake(MIN(260, maxWidth), 180);
        
    } else if (viewClass == [ChatNotificationCell class]) {
        size = [TTTAttributedLabel sizeThatFitsAttributedString:attributedString
                                                withConstraints:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                         limitedToNumberOfLines:0];
    } else {
        size = [TTTAttributedLabel sizeThatFitsAttributedString:attributedString
                                                withConstraints:CGSizeMake(maxWidth, CGFLOAT_MAX)
                                         limitedToNumberOfLines:0];
    }
    return size;
}



- (NSString *)collectionView:(ChatCollectionView *)collectionView
           itemIdAtIndexPath:(nonnull NSIndexPath *)indexPath {
    QBChatMessage *item = [self.dataSource messageWithIndexPath:indexPath];
    return item.ID;
}

#pragma mark - Collection view delegate - ContextMenu
- (UITargetedPreview *)targetedPreviewForConfiguration:(UIContextMenuConfiguration *)configuration {
    
    ChatCell *selectedCell = (ChatCell *)[self.collectionView cellForItemAtIndexPath:self.selectedIndexPathForMenu];
    UIPreviewParameters *parameters = [[UIPreviewParameters alloc] init];
    parameters.backgroundColor = [UIColor clearColor];
    
    CGFloat cornerRadius = [selectedCell isKindOfClass:[ChatAttachmentCell class]] ? 6.0f : 20.0f;
    
    UIRectCorner roundingCorners = UIRectCornerBottomLeft | UIRectCornerTopLeft | UIRectCornerTopRight;;
    
    QBChatMessage *message = [self.dataSource messageWithIndexPath:self.selectedIndexPathForMenu];
    if (message.senderID != self.senderID) {
        roundingCorners = UIRectCornerTopLeft | UIRectCornerTopRight | UIRectCornerBottomRight;
    }
    
    parameters.visiblePath = [UIBezierPath bezierPathWithRoundedRect:selectedCell.previewContainer.bounds
                                                   byRoundingCorners:roundingCorners
                                                         cornerRadii:CGSizeMake(cornerRadius, cornerRadius)];
    
    UITargetedPreview *targetedPreview = [[UITargetedPreview alloc] initWithView:selectedCell.previewContainer parameters:parameters];
    
    return targetedPreview;
}

- (UITargetedPreview *)collectionView:(UICollectionView *)collectionView previewForHighlightingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self targetedPreviewForConfiguration:configuration];
}

- (UITargetedPreview *)collectionView:(UICollectionView *)collectionView previewForDismissingContextMenuWithConfiguration:(UIContextMenuConfiguration *)configuration {
    return [self targetedPreviewForConfiguration:configuration];
}

- (UIContextMenuConfiguration *)collectionView:(UICollectionView *)collectionView contextMenuConfigurationForItemAtIndexPath:(NSIndexPath *)indexPath point:(CGPoint)point {
    [self hideKeyboard:YES];
    
    self.selectedIndexPathForMenu = indexPath;

    return [UIContextMenuConfiguration configurationWithIdentifier:nil previewProvider:nil actionProvider:^UIMenu * _Nullable(NSArray<UIMenuElement *> * _Nonnull suggestedActions) {
        ChatCell *cell = (ChatCell *)[self.collectionView cellForItemAtIndexPath:self.selectedIndexPathForMenu];
        if ([cell isKindOfClass:[ChatAttachmentCell class]]) {
            ChatAttachmentCell *chatAttachmentCell = (ChatAttachmentCell *)cell;
            QBChatMessage *item = [self.dataSource messageWithIndexPath:self.selectedIndexPathForMenu];
            QBChatAttachment *attachment = item.attachments.firstObject;
            
            if (attachment && attachment.ID && [attachment.type isEqualToString:@"file"]) {
                return [self chatContextMenuForCell:chatAttachmentCell];
            }
        }
        return nil;
    }];
}

#pragma mark - Text view delegate
- (void)textViewDidBeginEditing:(UITextView *)textView {
    if (textView != self.inputToolbar.contentView.textView) {
        return;
    }
    if (self.automaticallyScrollsToMostRecentMessage) {
        self.collectionBottomConstraint.constant = self.collectionBottomConstant;
        [self scrollToBottomAnimated:YES];
    }
}

- (void)textViewDidChange:(UITextView *)textView {
    if (textView != self.inputToolbar.contentView.textView) {
        return;
    }
    if ([textView.text hasPrefix:@" "]) {
        textView.text = [textView.text substringFromIndex:1];
    }
    
    if (textView.text.length > maxNumberLetters) {
        textView.text = [textView.text substringToIndex:NSMaxRange([textView.text rangeOfComposedCharacterSequenceAtIndex:maxNumberLetters - 1])];
    }

    [self.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
}

- (BOOL)textView:(UITextView *)textView shouldChangeTextInRange:(NSRange)range replacementText:(NSString *)text {
    if (textView != self.inputToolbar.contentView.textView) {
        return NO;
    }
    return YES;
}

#pragma mark - ChatCellDelegate
- (void)chatCellDidTapContainer:(ChatCell *)cell {
    if (![cell isKindOfClass:[ChatAttachmentCell class]]) {
        return;
    }
    ChatAttachmentCell *chatAttachmentCell = (ChatAttachmentCell *)cell;
    NSIndexPath *indexPath = [self.collectionView indexPathForCell:chatAttachmentCell];
    QBChatMessage *item = [self.dataSource messageWithIndexPath:indexPath];
    QBChatAttachment *attachment = item.attachments.firstObject;
    
    if (attachment && attachment.ID && [attachment.type isEqualToString:@"image"]) {
        UIImage *attachmentImage = chatAttachmentCell.attachmentImageView.image;
        if (attachmentImage) {
            ZoomedAttachmentViewController *zoomedVC = [[ZoomedAttachmentViewController alloc] initWithImage:attachmentImage];
            UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:zoomedVC];
            navVC.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:navVC animated:NO completion:nil];
        }
    } else if (attachment && attachment.ID && [attachment.type isEqualToString:@"video"]) {
        NSString *appendingPathComponent = [NSString stringWithFormat:@"%@_%@", attachment.ID, attachment.name];
        NSString *path = [NSString stringWithFormat:@"%@/%@", CacheManager.instance.cachesDirectory, appendingPathComponent];
        NSURL *videoURL = [NSURL fileURLWithPath:path];
        if ([NSFileManager.defaultManager fileExistsAtPath:videoURL.path]) {
            ParentVideoVC *parentVideoVC = [[ParentVideoVC alloc] initWithVideoUrl:videoURL];
            parentVideoVC.title = attachment.name;
            UINavigationController *navVC = [[UINavigationController alloc] initWithRootViewController:parentVideoVC];
            navVC.modalPresentationStyle = UIModalPresentationFullScreen;
            [self presentViewController:navVC animated:NO completion:nil];
        }
    }
}

- (void)saveFileAttachmentFromChatAttachmentCell:(ChatAttachmentCell *)chatAttachmentCell {
    NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    NSString *destinationPath = [NSString stringWithFormat:@"%@/%@", documentsPath, chatAttachmentCell.attachmentUrl.lastPathComponent];
    
    if ([NSFileManager.defaultManager fileExistsAtPath:destinationPath]) {
        [NSFileManager.defaultManager removeItemAtPath:destinationPath error:nil];
    }
    
    NSError *error = nil;
    [NSFileManager.defaultManager copyItemAtPath:chatAttachmentCell.attachmentUrl.path toPath:destinationPath error:&error];
    if (error) {
        [SVProgressHUD showErrorWithStatus:@"Save error"];
    } else {
        [SVProgressHUD showSuccessWithStatus:@"Saved!"];
    }
}

- (void)openAttachmentImage:(UIImage *)image {
    ZoomedAttachmentViewController *zoomedVC = [[ZoomedAttachmentViewController alloc] initWithImage:image];
    zoomedVC.modalPresentationStyle = UIModalPresentationOverCurrentContext;
    zoomedVC.modalTransitionStyle = UIModalTransitionStyleCrossDissolve;
    [self presentViewController:zoomedVC animated:YES completion:nil];
}

#pragma mark - QBChatDelegate
- (void)chatDidReadMessageWithID:(NSString *)messageID
                        dialogID:(NSString *)dialogID
                        readerID:(NSUInteger)readerID {
    if (self.senderID == readerID || ![dialogID isEqualToString:self.dialog.ID]) {
        return;
    }
    QBChatMessage *currentMessage = [self.dataSource messageWithID:messageID];
    if (currentMessage) {
        NSMutableArray *readIDs = [currentMessage.readIDs mutableCopy];
        if ([readIDs containsObject:@(readerID)]) {
            return;
        }
        [readIDs addObject:@(readerID)];
        [currentMessage setReadIDs: [readIDs copy]];
        [self.dataSource updateMessage:currentMessage];
    }
}

- (void)chatDidDeliverMessageWithID:(NSString *)messageID dialogID:(NSString *)dialogID toUserID:(NSUInteger)userID {
    if (self.senderID == userID || ![dialogID isEqualToString:self.dialog.ID]) {
        return;
    }
    QBChatMessage *currentMessage = [self.dataSource messageWithID:messageID];
    if (currentMessage) {
        QBChatMessage *currentMessage = [self.dataSource messageWithID:messageID];
        NSMutableArray *deliveredIDs = [currentMessage.deliveredIDs mutableCopy];
        if ([deliveredIDs containsObject:@(userID)]) {
            return;
        }
        [deliveredIDs addObject:@(userID)];
        [currentMessage setDeliveredIDs: [deliveredIDs copy]];
        [self.dataSource updateMessage:currentMessage];
    }
}

- (void)chatDidReceiveMessage:(QBChatMessage *)message {
    if ([message.dialogID isEqualToString: self.dialog.ID] && message.senderID != self.senderID) {
        [self.dataSource addMessage:message];
    }
}

- (void)chatRoomDidReceiveMessage:(QBChatMessage *)message fromDialogID:(NSString *)dialogID {
    if ([dialogID isEqualToString: self.dialog.ID] && message.senderID != self.senderID) {
        [self.dataSource addMessage:message];
    }
}

- (void)refreshAndReadMessages {
    // Autojoin to the group chat
    if (!self.dialog.isJoined) {
        [self.dialog joinWithCompletionBlock:^(NSError *error) {
            if (error) {
                Log(@"[%@] dialog join error: %@",
                    NSStringFromClass([ChatViewController class]),
                    error.localizedDescription);
            }
        }];
    }
    // Handling unread messages
    if ([self.dataSource messagesForReadCount] > 0) {
        NSArray *messages = [self.dataSource allMessagesForRead];
        __weak typeof(self)weakSelf = self;
        for (QBChatMessage *message in messages) {
            [self.chatManager readMessage:message dialog:self.dialog completion:^(NSError * _Nullable error) {
                __typeof(weakSelf)strongSelf = weakSelf;
                if (!error) {
                    NSMutableArray *readIDs = [message.readIDs mutableCopy];
                    [readIDs addObject:@(QBChat.instance.currentUser.ID)];
                    [message setReadIDs: [readIDs copy]];
                    [strongSelf.dataSource updateMessage:message];
                    [strongSelf.dataSource removeMessageForRead:message];
                }
            }];
        }
    }
    // Handling unsent messages
    if ([self.dataSource draftMessagesCount] > 0) {
        NSArray *messages = [self.dataSource allDraftMessages];
        __weak typeof(self)weakSelf = self;
        for (QBChatMessage *message in messages) {
            [self.dialog sendMessage:message completionBlock:^(NSError * _Nullable error) {
                __typeof(weakSelf)strongSelf = weakSelf;
                if (error) {
                    Log(error.localizedDescription);
                    return;
                }
                [strongSelf.dataSource removeDraftMessage:message];
                [strongSelf.dataSource addMessage:message];
            }];
        }
    }
    
    [self loadMessagesWithSkip:0];
    [self.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
}

#pragma mark - AttachmentBarDelegateUIPopoverPresentationControllerDelegate
- (void)attachmentBarFailedUpLoadImage:(AttachmentUploadBar *)attachmentBar {
    [self cancelUploadFile];
}

- (void)attachmentBar:(AttachmentUploadBar *)attachmentBar didUpLoadAttachment:(QBChatAttachment *)attachment {
    self.attachmentMessage = [self createAttachmentMessageWith:attachment];
    [self.inputToolbar toggleSendButtonEnabledIsUploaded:self.isUploading];
}

- (void)attachmentBar:(AttachmentUploadBar *)attachmentBar didTapCancelButton:(UIButton *)sender {
    self.attachmentMessage = nil;
    [self hideAttacnmentBar];
}

#pragma mark - ChatConextMenuProtocol

#pragma mark Chat Manager Delegate
- (void)chatManager:(ChatManager *)chatManager didUpdateChatDialog:(QBChatDialog *)chatDialog {
    if (![chatDialog.ID isEqualToString:self.dialog.ID]) {
        return;
    }
    [self setupTitleView];
}

//MARK: - ChatManagerConnectionDelegate
- (void)chatManagerConnect:(ChatManager *)chatManager {
    [self refreshAndReadMessages];
    [SVProgressHUD showSuccessWithStatus:@"Connected!"];
}

- (void)chatManagerDisconnect:(ChatManager *)chatManager withLostNetwork:(BOOL)lostNetwork {
    if (lostNetwork == NO) { return; }
    if ([self.presentedViewController isKindOfClass:[Alert class]]) {
        Alert *alert = (Alert *)self.presentedViewController;
        if (alert.isPresented) {
            return;
        }
    }
    [self showAlertWithTitle:@"No Internet Connection" message:@"Make sure your device is connected to the internet" fromViewController:self];
}

@end
