# Overview
The VideoChat code sample allows you to easily add video calling and audio calling features into your iOS app with [QuickBlox](https://quickblox.com). Enable a video call function similar to FaceTime or Skype using this code sample as a basis.

It is based on WebRTC technology.

This code sample is written in *Objective-C* lang.
The same is also available in [Swift](https://github.com/QuickBlox/quickblox-ios-sdk/blob/master/sample-videochat-webrtc-swift) lang.

# Get Application Credentials

QuickBlox application includes everything that brings messaging right into your application - chat, video calling, users, push notifications, etc. To create a QuickBlox application, follow the steps below:

1. Register a new account following this [link](https://admin.quickblox.com/signup). Type in your email and password to sign in. You can also sign in with your Google or Github accounts.
2. Create the app clicking **New app** button.
3. Configure the app. Type in the information about your organization into corresponding fields and click **Add** button.
4. Go to **Dashboard => *YOUR_APP* => Overview** section and copy your **Application ID**,  **Authorization Key**,  **Authorization Secret**,  and **Account Key** .


# Features

It allows to:

1. Login/logout with Quickblox Chat and REST.
2. Display a list of users.
3. Make and receive 1-to-1 and group audio call.
4. Make and receive 1-to-1 and group video call.
5. Search for users to make a call with.
6. Mute/unmute the microphone.
7. Display the list of call participants and their statuses.
8. Share a screen.
9. Switch camera.
10. See call timer.
11. Receive call stats report.
12. Change setting (media settings, answer time interval, etc.).
13. Switch speaker.
14. Display bitrate. 
15. [CallKit](https://developer.apple.com/documentation/callkit) supported.
16. WebRTC Stats reports.
17. Send/receive VOIP [push notification](https://docs.quickblox.com/docs/ios-push-notifications).
18. Subscribe/unsubscribe device to VOIP [push notification](https://docs.quickblox.com/docs/ios-push-notifications).

# The Сhanges VOIP on iOS 13

With the changes VOIP on iOS 13 enforced and outlined in https://developer.apple.com/videos/play/wwdc2019/707/ and https://developer.apple.com/documentation/pushkit/pkpushregistrydelegate/2875784-pushregistry/,
Now, when we receive a VOIP Push in the background, we are forced to immediately report an incoming call before the session of this call arrives. To improve user experience, we added some additional information about this call to the VoIP payload of the outgoing call push:

let payload = ["message": "\(opponentName) is calling you.",
    "ios_voip": "1",
    "VOIPCall": "1",
    "sessionID": session.id, - this is the session ID (String) that the call initiator created, added to payload so that the opponent can know the session ID that should arrive to him and correctly manage incoming sessions;
    "opponentsIDs": allUsersIDsString, - this is the string from the IDs of all participants in the call, separated by a comma, with the initiator in the first place, in payload, added so that the opponent could know the opponentsIDs of this session before the session;
    "contactIdentifier": allUsersNamesString, - this is the string from fullName of all call participants separated by a comma, with the initiator in the first place !!!, added to payload so that the opponent could know the names of the participants of this session before the session arrives and display them on the CallKit screen;
    "conferenceType" : conferenceTypeString - this is the string (let conferenceTypeString = conferenceType == .video? "1": “2”), added to payload so that the opponent can know the conferenceType (“video” or “audio”) of this session before the session arrives and correctly configure the CallKit screen;
    “timestamp”: timestamp - this is the string from the date of sending the VOIP Push, it's added to payload for the case when there is bad Internet  and the push is delivered for a long time and may come when the call initiator completes the call automatically. Upon receiving  of the push, we compare the date of departure and the date of receiving and if the delivery time of the push is longer than “answerTimeInterval” - do not show the call;
]

# Run Video Chat Sample

To run a code sample, follow the steps below:

1. Install [CocoaPods](https://cocoapods.org) to manage project dependencies.

```
bash
$ sudo gem install cocoapods
```
2. Clone repository with the sample code.
3. Open a terminal and enter the command below in your project path to integrate QuickBlox into the sample.
```
bash
$ pod install
```
4. [Get application credentials](#get-application-credentials).
5. Put the received credentials in ```AppDelegate``` file located in the root directory of your project.

```
[QBSettings setApplicationID:92];
[QBSettings setAuthKey:@"wJHdOcQSxXQGWx5"];
[QBSettings setAuthSecret:@"BTFsj7Rtt27DAmT"];
[QBSettings setAccountKey:@"7yvNe17TnjNUqDoPwfqp"];
```
6. Run the code sample.
