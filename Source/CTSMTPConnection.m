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

#import "CTSMTPConnection.h"
#import <libetpan/libetpan.h>
#import "CTCoreAddress.h"
#import "CTCoreMessage.h"
#import "MailCoreTypes.h"

#import "CTSMTP.h"
#import "CTESMTP.h"

//TODO Add more descriptive error messages using mailsmtp_strerror
@implementation CTSMTPConnection

static void send_progress_callback(size_t current, size_t maximum, void * context) {
    CTSendProgressBlock block = context;
    block(current, maximum);
}

+ (BOOL)sendMessage:(NSData *)render from:(CTCoreAddress *)from rcpts:(NSSet *)rcpts server:(NSString *)server username:(NSString *)username
                   password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
                    useAuth:(BOOL)auth authType:(int)authType progress:(CTSendProgressBlock)block  connectionTimeout:(time_t)connectionTimeout uploadTimeout:(time_t)uploadTimeout error:(NSError **)error {
    BOOL success;
    mailsmtp *smtp = NULL;
    smtp = mailsmtp_new(0, NULL);
    if (connectionTimeout > 0) {
        mailsmtp_set_timeout(smtp, connectionTimeout);
    }
    
    CTSMTP *smtpObj = [[CTESMTP alloc] initWithResource:smtp];
    if (connectionType == CTSMTPConnectionTypeStartTLS || connectionType == CTSMTPConnectionTypePlain) {
        success = [smtpObj connectToServer:server port:port];
    } else if (connectionType == CTSMTPConnectionTypeTLS) {
        success = [smtpObj connectWithTlsToServer:server port:port];
    }
    if (!success) {
        goto error;
    }
    
    if (uploadTimeout > 0 && smtp->stream != NULL) {
        smtp->stream->low->timeout = uploadTimeout;
    }
    
    if ([smtpObj helo] == NO) {
        /* The server didn't support ESMTP, so switching to STMP */
        [smtpObj release];
        smtpObj = [[CTSMTP alloc] initWithResource:smtp];
        success = [smtpObj helo];
        if (!success) {
            goto error;
        }
    }
    if (connectionType == CTSMTPConnectionTypeStartTLS) {
        success = [smtpObj startTLS];
        if (!success) {
            goto error;
        }
    }
    if (auth) {
        success = [smtpObj authenticateWithUsername:username password:password server:server authType:authType];
        if (!success) {
            goto error;
        }
    }
    
    success = [smtpObj setFrom:[from email]];
    if (!success) {
        goto error;
    }
    

    success = [smtpObj setRecipients:rcpts];
    if (!success) {
        goto error;
    }
    
    if (block) {
        mailsmtp_set_progress_callback(smtp, &send_progress_callback, block);
    }
    
    /* data */
    const char* bytes = [render bytes];
    NSUInteger length = [render length];
    
    success = [smtpObj setData:bytes length:length];
    
    if (block) {
        mailsmtp_set_progress_callback(smtp, NULL, NULL);
    }
    
    if (!success) {
        goto error;
    }
    
    mailsmtp_quit(smtp);
    mailsmtp_free(smtp);
    
    [smtpObj release];
    return YES;
error:
    *error = smtpObj.lastError;
    [smtpObj release];
    mailsmtp_free(smtp);
    return NO;
}

+ (BOOL)sendMessage:(CTCoreMessage *)message server:(NSString *)server username:(NSString *)username
           password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth authType:(int)authType progress:(CTSendProgressBlock)block  connectionTimeout:(time_t)connectionTimeout uploadTimeout:(time_t)uploadTimeout error:(NSError **)error {
    /* recipients */
    NSMutableSet *rcpts = [NSMutableSet set];
    [rcpts unionSet:[message to]];
    [rcpts unionSet:[message bcc]];
    [rcpts unionSet:[message cc]];
    
    return [self sendMessage:[[message render] dataUsingEncoding:NSUTF8StringEncoding] from:[message.from anyObject] rcpts:rcpts server:server username:username password:password port:port connectionType:connectionType useAuth:auth authType:authType progress:block connectionTimeout:connectionTimeout uploadTimeout:uploadTimeout error:error];
}

+ (BOOL)sendMessage:(CTCoreMessage *)message server:(NSString *)server username:(NSString *)username password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType useAuth:(BOOL)auth authType:(int)authType progress:(CTSendProgressBlock)block error:(NSError **)error {
    return [self sendMessage:message server:server username:username password:password port:port connectionType:connectionType useAuth:auth authType:authType progress:block connectionTimeout:0 uploadTimeout:0 error:error];
}

+ (BOOL)sendMessage:(CTCoreMessage *)message server:(NSString *)server username:(NSString *)username
           password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
            useAuth:(BOOL)auth authType:(int)authType error:(NSError **)error {
    return [self sendMessage:message server:server username:username password:password port:port connectionType:connectionType useAuth:auth authType:authType progress:nil error:error];
}


+(BOOL)sendMessage:(CTCoreMessage *)message server:(NSString *)server username:(NSString *)username password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType useAuth:(BOOL)auth error:(NSError **)error {
    return [self sendMessage:message server:server username:username password:password port:port connectionType:connectionType useAuth:auth authType:MAILSMTP_AUTH_PLAIN error:error];
}



+ (BOOL)canConnectToServer:(NSString *)server username:(NSString *)username password:(NSString *)password
                      port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType
                   useAuth:(BOOL)auth authType:(int)authType error:(NSError **)error {
  BOOL success;
  mailsmtp *smtp = NULL;
  smtp = mailsmtp_new(0, NULL);
    
  CTSMTP *smtpObj = [[CTESMTP alloc] initWithResource:smtp];
  if (connectionType == CTSMTPConnectionTypeStartTLS || connectionType == CTSMTPConnectionTypePlain) {
     success = [smtpObj connectToServer:server port:port];
  } else if (connectionType == CTSMTPConnectionTypeTLS) {
     success = [smtpObj connectWithTlsToServer:server port:port];
  }
  if (!success) {
    goto error;
  }
  if ([smtpObj helo] == NO) {
    /* The server didn't support ESMTP, so switching to STMP */
    [smtpObj release];
    smtpObj = [[CTSMTP alloc] initWithResource:smtp];
    success = [smtpObj helo];
    if (!success) {
      goto error;
    }
  }
  if (connectionType == CTSMTPConnectionTypeStartTLS) {
    success = [smtpObj startTLS];
    if (!success) {
      goto error;
    }
  }
  if (auth) {
    success = [smtpObj authenticateWithUsername:username password:password server:server authType:authType];
    if (!success) {
      goto error;
    }
  }

  mailsmtp_quit(smtp);
  mailsmtp_free(smtp);
    
  [smtpObj release];
  return YES;
error:
  *error = smtpObj.lastError;
  [smtpObj release];
  mailsmtp_free(smtp);
  return NO;
}


+ (BOOL)canConnectToServer:(NSString *)server username:(NSString *)username password:(NSString *)password port:(unsigned int)port connectionType:(CTSMTPConnectionType)connectionType useAuth:(BOOL)auth error:(NSError **)error {
    return [self canConnectToServer:server username:username password:password port:port connectionType:connectionType useAuth:auth authType:MAILSMTP_AUTH_PLAIN error:error];
}



@end
