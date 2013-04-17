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

#import "CTESMTP.h"

#import "CTCoreAddress.h"
#import "CTCoreMessage.h"
#import "MailCoreTypes.h"
#import "MailCoreUtilities.h"

#include <sys/types.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>

/* Code from Dinh Viet Hoa */
static int fill_remote_ip_port(mailstream * stream, char * remote_ip_port, size_t remote_ip_port_len) {
  mailstream_low * low;
  int fd;
  struct sockaddr_in name;
  socklen_t namelen;
  char remote_ip_port_buf[128];
  int r;

  low = mailstream_get_low(stream);
  fd = mailstream_low_get_fd(low);

  namelen = sizeof(name);
  r = getpeername(fd, (struct sockaddr *) &name, &namelen);
  if (r < 0)
    return -1;

  if (inet_ntop(AF_INET, &name.sin_addr, remote_ip_port_buf,
          sizeof(remote_ip_port_buf)))
    return -1;

  snprintf(remote_ip_port, remote_ip_port_len, "%s;%i",
      remote_ip_port_buf, ntohs(name.sin_port));

  return 0;
}


static int fill_local_ip_port(mailstream * stream, char * local_ip_port, size_t local_ip_port_len) {
  mailstream_low * low;
  int fd;
  struct sockaddr_in name;
  socklen_t namelen;
  char local_ip_port_buf[128];
  int r;

  low = mailstream_get_low(stream);
  fd = mailstream_low_get_fd(low);
  namelen = sizeof(name);
  r = getpeername(fd, (struct sockaddr *) &name, &namelen);
  if (r < 0)
    return -1;

  if (inet_ntop(AF_INET, &name.sin_addr, local_ip_port_buf, sizeof(local_ip_port_buf)))
    return -1;

  snprintf(local_ip_port, local_ip_port_len, "%s;%i", local_ip_port_buf, ntohs(name.sin_port));
  return 0;
}

@implementation CTESMTP

- (BOOL)helo {
    int ret = mailesmtp_ehlo([self resource]);
    /* Return false if the server doesn't implement ehlo */
    return (ret != MAILSMTP_ERROR_NOT_IMPLEMENTED);
}


- (BOOL)startTLS {
    int ret = mailsmtp_socket_starttls([self resource]);
    if (ret != MAIL_NO_ERROR) {
        self.lastError = MailCoreCreateErrorFromSMTPCode(ret);
        return NO;
    }

    ret = mailesmtp_ehlo([self resource]);
    if (ret != MAIL_NO_ERROR) {
        self.lastError = MailCoreCreateErrorFromSMTPCode(ret);
        return NO;
    }
    return YES;
}


- (BOOL)authenticateWithUsername:(NSString *)username password:(NSString *)password server:(NSString *)server {
    return [self authenticateWithUsername:username password:password server:server authType:MAILSMTP_AUTH_PLAIN];
}


- (BOOL)authenticateWithUsername:(NSString *)username password:(NSString *)password server:(NSString *)server authType:(int)authType {
    char *cUsername = (char *)[username cStringUsingEncoding:NSUTF8StringEncoding];
    char *cPassword = (char *)[password cStringUsingEncoding:NSUTF8StringEncoding];
    char *cServer = (char *)[server cStringUsingEncoding:NSUTF8StringEncoding];
    
    char local_ip_port_buf[128];
    char remote_ip_port_buf[128];
    char * local_ip_port;
    char * remote_ip_port;
    
    if (cPassword == NULL)
        cPassword = "";
    if (cUsername == NULL)
        cUsername = "";
    
    int ret = fill_local_ip_port([self resource]->stream, local_ip_port_buf, sizeof(local_ip_port_buf));
    if (ret < 0)
        local_ip_port = NULL;
    else
        local_ip_port = local_ip_port_buf;
    
    ret = fill_remote_ip_port([self resource]->stream, remote_ip_port_buf, sizeof(remote_ip_port_buf));
    if (ret < 0)
        remote_ip_port = NULL;
    else
        remote_ip_port = remote_ip_port_buf;
    /*
     in most case, login = auth_name = user@domain
     and realm = server hostname full qualified domain name
     */
    
    
    char *authTypeStr = "PLAIN";
    mailsmtp *session = [self resource];
    if (session->auth & MAILSMTP_AUTH_CHECKED) {
        if ((authType & session->auth) == 0) {
            // it means authType requested is not supported by smtp server.
            // Choose a type supported.
            if ((authType & MAILSMTP_AUTH_PLAIN) != 0) {
                // Check PLAIN first
                authType = MAILSMTP_AUTH_PLAIN;
            } else {
                unsigned int mask = 2;
                while ((mask & session->auth) == 0 && session->auth < MAILSMTP_AUTH_XOAUTH2) {
                    mask = 2 * mask;
                }
                // TODO: There is a tiny oppotunity that mask may be greater than MAILSMTP_AUTH_XOAUTH2. Should return error here.
                authType = mask;
            }
        }
    } else {
        authType = MAILSMTP_AUTH_PLAIN;
    }
    
    switch (authType) {
        case MAILSMTP_AUTH_XOAUTH2:
            authTypeStr = "XOAUTH2";
            break;
            
        case MAILSMTP_AUTH_LOGIN:
            authTypeStr = "LOGIN";
            break;
            
        case MAILSMTP_AUTH_CRAM_MD5:
            authTypeStr = "CRAM-MD5";
            break;
            
        case MAILSMTP_AUTH_DIGEST_MD5:
            authTypeStr = "DIGEST-MD5";
            break;
            
        case MAILSMTP_AUTH_GSSAPI:
            authTypeStr = "GSSAPI";
            break;
            
        case MAILSMTP_AUTH_NTLM:
            authTypeStr = "NTLM";
            break;
            
        case MAILSMTP_AUTH_SRP:
            authTypeStr = "SRP";
            break;
            
        case MAILSMTP_AUTH_KERBEROS_V4:
            authTypeStr = "KERBEROS_V4";
            break;

        default:
            break;
    }

    ret = mailesmtp_auth_sasl(session, authTypeStr, cServer, local_ip_port, remote_ip_port,
                              cUsername, cUsername, cPassword, cServer);

    if (ret != MAIL_NO_ERROR) {
        self.lastError = MailCoreCreateErrorFromSMTPCode(ret);
        return NO;
    }
    return YES;
}

/**
 * useless now.
 */
- (char *) authtype:(int) type
{
    switch (type&~MAILSMTP_AUTH_CHECKED) {
        case MAILSMTP_AUTH_CRAM_MD5:
            return "CRAM-MD5";
        case MAILSMTP_AUTH_PLAIN:
            return "PLAIN";
        case MAILSMTP_AUTH_GSSAPI:
            return "GSSAPI";
        case MAILSMTP_AUTH_DIGEST_MD5:
            return "DIGEST-MD5";
        case MAILSMTP_AUTH_LOGIN:
            return "LOGIN";
        case MAILSMTP_AUTH_SRP:
            return "SRP";
        case MAILSMTP_AUTH_NTLM:
            return "NTLM";
        case MAILSMTP_AUTH_KERBEROS_V4:
            return "KERBEROS_V4";
        default:
            break;
    }
    return "PLAIN";
}


- (BOOL)setFrom:(NSString *)fromAddress {
    int ret = mailesmtp_mail([self resource], [fromAddress cStringUsingEncoding:NSUTF8StringEncoding], 1, "MailCoreSMTP");
    if (ret != MAIL_NO_ERROR) {
        self.lastError = MailCoreCreateErrorFromSMTPCode(ret);
        return NO;
    }
    return YES;
}


- (BOOL)setRecipientAddress:(NSString *)recAddress {
    int ret = mailesmtp_rcpt([self resource], [recAddress cStringUsingEncoding:NSUTF8StringEncoding],
                        MAILSMTP_DSN_NOTIFY_FAILURE|MAILSMTP_DSN_NOTIFY_DELAY,NULL);
    if (ret != MAIL_NO_ERROR) {
        self.lastError = MailCoreCreateErrorFromSMTPCode(ret);
        return NO;
    }
    return YES;
}
@end
