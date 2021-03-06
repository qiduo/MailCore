/*
 * MailCore
 *
 * Copyright (C) 2007 - Matt Ronge
 * All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 * 3. Neither the name of the MailCore project nor the names of its
 *    contributors may be used to endorse or promote products derived
 *    from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE AUTHORS AND CONTRIBUTORS ``AS IS'' AND
 * ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHORS OR CONTRIBUTORS BE LIABLE
 * FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
 * OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
 * HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
 * SUCH DAMAGE.
 */

#import <Foundation/Foundation.h>
#import "MailCoreTypes.h"

typedef void (^CTSendProgressBlock)(size_t curr, size_t max);

/**
 This is not a class you instantiate! It has only two class methods, and that is all you need to send e-mail.
 First use CTCoreMessage to compose an e-mail and then pass the e-mail to the method sendMessage: with
 the necessary server settings and CTSMTPConnection will send the message.
*/

@class CTCoreMessage, CTCoreAddress, CTSMTP;

@interface CTSMTPConnection : NSObject {

}

@property (nonatomic,strong) CTSMTP *smtpObj;


/**
 This method...it sends e-mail.
 @param message	Just pass in a CTCoreMessage which has the body, subject, from, to etc. that you want
 @param server The server address
 @param username The username, if there is none then pass in an empty string. For some servers you may have to specify the username as username@domain
 @param password The password, if there is none then pass in an empty string.
 @param port The port to use, the standard port is 25
 @param connectionType What kind of connection, either: CTSMTPConnectionTypePlain, CTSMTPConnectionTypeStartTLS, CTSMTPConnectionTypeTLS
 @param auth Pass in YES if you would like to use SASL authentication
 @param error Will contain an error when the method returns NO
 @return Returns YES on success, NO on error
*/
+ (BOOL)sendMessage:(CTCoreMessage *)message
             server:(NSString *)server
           username:(NSString *)username
           password:(NSString *)password
               port:(unsigned int)port
     connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth
              error:(NSError **)error;

/**
 * @param authType. enum MAILSMTP_AUTH_PLAIN / MAILSMTP_AUTH_XOAUTH2 ...
 */
+ (BOOL)sendMessage:(CTCoreMessage *)message
             server:(NSString *)server
           username:(NSString *)username
           password:(NSString *)password
               port:(unsigned int)port
     connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth
           authType:(int)authType
              error:(NSError **)error;

/**
 * @param connectionTimeout, timeout for connection to server 
   @param uploadTimeout, timeout for uploading
 */
+ (BOOL)sendMessage:(CTCoreMessage *)message server:(NSString *)server username:(NSString *)username
           password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth authType:(int)authType progress:(CTSendProgressBlock)block  connectionTimeout:(time_t)connectionTimeout uploadTimeout:(time_t)uploadTimeout error:(NSError **)error;


/**
 * @param block the call back block for send mail progress, can be nil
 */
+ (BOOL)sendMessage:(CTCoreMessage *)message
             server:(NSString *)server
           username:(NSString *)username
           password:(NSString *)password
               port:(unsigned int)port
     connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth
           authType:(int)authType
           progress:(CTSendProgressBlock)block
              error:(NSError **)error;

/**
 * @param render is mail's raw content
   @param from is mail's from
   @param rcpts include to,cc,bcc
 */
+ (BOOL)sendMessage:(NSData *)render
               from:(CTCoreAddress *)from
              rcpts:(NSSet *)rcpts
             server:(NSString *)server
           username:(NSString *)username
           password:(NSString *)password
               port:(unsigned int)port
     connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth
           authType:(int)authType
           progress:(CTSendProgressBlock)block
  connectionTimeout:(time_t)connectionTimeout
      uploadTimeout:(time_t)uploadTimeout
              error:(NSError **)error;

- (BOOL)sendMessage:(NSData *)render
               from:(CTCoreAddress *)from
              rcpts:(NSSet *)rcpts
             server:(NSString *)server
           username:(NSString *)username
           password:(NSString *)password
               port:(unsigned int)port
     connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth
           authType:(int)authType
           progress:(CTSendProgressBlock)block
  connectionTimeout:(time_t)connectionTimeout
      uploadTimeout:(time_t)uploadTimeout
              error:(NSError **)error;

/**
 Use this method to test the user's credentials.
 
 This is useful for account setup. You can have the user enter in their credentials and then verify they work without sending a message.
 @param server The server address
 @param username The username, if there is none then pass in an empty string. For some servers you may have to specify the username as username@domain
 @param password The password, if there is none then pass in an empty string.
 @param port The port to use, the standard port is 25
 @param connectionType What kind of connection, either: CTSMTPConnectionTypePlain, CTSMTPConnectionTypeStartTLS, CTSMTPConnectionTypeTLS
 @param auth Pass in YES if you would like to use SASL authentication
 @param error Will contain an error when the method returns NO
 @return Returns YES on success, NO on error
 */
+ (BOOL)canConnectToServer:(NSString *)server
                  username:(NSString *)username
                  password:(NSString *)password
                      port:(unsigned int)port
            connectionType:(CTSMTPConnectionType)connectionType
                   useAuth:(BOOL)auth
                     error:(NSError **)error;

/**
 * cancel sending mail
 */
- (void)cancel;

/**
 * @param authType. enum MAILSMTP_AUTH_PLAIN / MAILSMTP_AUTH_XOAUTH2 ...
 */
+ (BOOL)canConnectToServer:(NSString *)server
                  username:(NSString *)username
                  password:(NSString *)password
                      port:(unsigned int)port
            connectionType:(CTSMTPConnectionType)connectionType
                   useAuth:(BOOL)auth
                  authType:(int)authType
                     error:(NSError **)error;



@end
