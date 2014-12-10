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

#import "CTMIME_SinglePart.h"

#import <libetpan/libetpan.h>
#import "MailCoreTypes.h"
#import "MailCoreUtilities.h"


static inline struct imap_session_state_data *
get_session_data(mailmessage * msg)
{
    return msg->msg_session->sess_data;
}

static inline mailimap * get_imap_session(mailmessage * msg)
{
    return get_session_data(msg)->imap_session;
}

static void download_progress_callback(size_t current, size_t maximum, void * context) {
    CTProgressBlock block = context;
    block(current, maximum);
}

@interface CTMIME_SinglePart ()
@end

@implementation CTMIME_SinglePart
@synthesize attached=mAttached;
@synthesize filename=mFilename;
@synthesize contentId=mContentId;
@synthesize data=mData;
@synthesize fetched=mFetched;
@synthesize lastError;

+ (id)mimeSinglePartWithData:(NSData *)data {
    return [[[CTMIME_SinglePart alloc] initWithData:data] autorelease];
}

- (id)initWithData:(NSData *)data {
    self = [super init];
    if (self) {
        self.data = data;
        self.fetched = YES;
    }
    return self;
}

- (id)initWithMIMEStruct:(struct mailmime *)mime 
        forMessage:(struct mailmessage *)message {
    self = [super initWithMIMEStruct:mime forMessage:message];
    if (self) {
        mMime = mime;
        mMessage = message;
        self.fetched = NO;
        mMimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        [self getMimeData];

        if (mMimeFields != NULL) {
            if (mMimeFields->fld_id != NULL) {
                self.contentId = [NSString stringWithCString:mMimeFields->fld_id encoding:NSUTF8StringEncoding];
            }
            
            struct mailmime_disposition *disp = mMimeFields->fld_disposition;
            if (disp != NULL) {
                if (disp->dsp_type != NULL) {
                    self.attached = (disp->dsp_type->dsp_type == MAILMIME_DISPOSITION_TYPE_ATTACHMENT ||
                                     disp->dsp_type->dsp_type == MAILMIME_DISPOSITION_TYPE_INLINE);

                    if (self.attached)
                    {
                        // MWA workaround for bug where specific emails look like this:
                        // Content-Type: application/vnd.ms-excel; name="=?UTF-8?B?TVhBVC0zMTFfcGFja2xpc3QxMTA0MDAueGxz?="
                        // Content-Disposition: attachment
                        // - usually they look like -
                        // Content-Type: image/jpeg; name="photo.JPG"
                        // Content-Disposition: attachment; filename="photo.JPG"
                        if (mMimeFields->fld_disposition_filename == NULL && mMimeFields->fld_content_name != NULL)
                            mMimeFields->fld_disposition_filename = mMimeFields->fld_content_name;
                    }
                }
            }

            if (mMimeFields->fld_disposition_filename != NULL) {
                self.filename = MailCoreDecodeMIMEPhrase(mMimeFields->fld_disposition_filename);
                /*
                if (!self.filename||[self.filename isEqualToString:@""]) {
                    CFStringRef cfstr = CFStringCreateWithCString(NULL, mMimeFields->fld_content_name, kCFStringEncodingGB_18030_2000);
                    self.filename= [( NSString *)cfstr copy];
                }
                */
                if (mMimeFields->fld_id != NULL)
                    self.contentId = [NSString stringWithCString:mMimeFields->fld_id encoding:NSUTF8StringEncoding];
                
                self.attached = YES;
                
            }else if (mMimeFields->fld_content_name != NULL){
                if (mMimeFields->fld_content_charset) {
                    char *data= mMimeFields->fld_content_name;
                    size_t currToken = 0;
                    char *decodedSubject = NULL;
                    mailmime_encoded_phrase_parse(mMimeFields->fld_content_charset, data, strlen(data),
                                                            &currToken, DEST_CHARSET, &decodedSubject);
                    if (decodedSubject != NULL) {
                        self.filename = MailCoreDecodeMIMEPhrase(decodedSubject);
                        free(decodedSubject);
                    } else {
                        self.filename = MailCoreDecodeMIMEPhrase(data);
                    }

                }else{
                    self.filename = MailCoreDecodeMIMEPhrase(mMimeFields->fld_content_name);
                }
                self.attached = YES;
            }
        }
    }
    return self;
}

- (void) getMimeData
{
    if (mMime->mm_body) {
        struct mailmime_data * data;
        const char * bytes;
        size_t length;
        NSData * result;
                
        data = mMime->mm_data.mm_single;
        bytes = data->dt_data.dt_text.dt_data;
        length = data->dt_data.dt_text.dt_length;
        switch (data->dt_encoding) {
            case MAILMIME_MECHANISM_7BIT:
            case MAILMIME_MECHANISM_8BIT:
            case MAILMIME_MECHANISM_BINARY:
            case MAILMIME_MECHANISM_TOKEN:
            {
                result=[NSData dataWithBytes:bytes length:length];
                break;
            }
                
            case MAILMIME_MECHANISM_QUOTED_PRINTABLE:
            case MAILMIME_MECHANISM_BASE64:
            {
                char * decoded;
                size_t decoded_length;
                size_t cur_token;
                
                cur_token = 0;
                mailmime_part_parse(bytes, length, &cur_token,
                                    data->dt_encoding, &decoded, &decoded_length);
                result=[NSData dataWithBytes:decoded length:decoded_length];
                mailmime_decoded_part_free(decoded);
                break;
            }
        }
        self.data = result;
    }
}

- (BOOL)fetchPartWithProgress:(CTProgressBlock)block {
    if (self.fetched == NO) {
        struct mailmime_single_fields *mimeFields = NULL;

        int encoding = MAILMIME_MECHANISM_8BIT;
        mimeFields = mailmime_single_fields_new(mMime->mm_mime_fields, mMime->mm_content_type);
        if (mimeFields != NULL && mimeFields->fld_encoding != NULL)
            encoding = mimeFields->fld_encoding->enc_type;

        char *fetchedData = NULL;
        size_t fetchedDataLen;
        int r;

        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), &download_progress_callback, NULL, block);  
        }
        r = mailmessage_fetch_section(mMessage, mMime, &fetchedData, &fetchedDataLen);
        if (mMessage->msg_session != NULL) {
            mailimap_set_progress_callback(get_imap_session(mMessage), NULL, NULL, NULL); 
        }
        if (r != MAIL_NO_ERROR) {
            if (fetchedData) {
                mailmessage_fetch_result_free(mMessage, fetchedData);
            }
            self.lastError = MailCoreCreateErrorFromIMAPCode(r);
            return NO;
        }


        size_t current_index = 0;
        char * result=NULL;
        size_t result_len;
        r = mailmime_part_parse(fetchedData, fetchedDataLen, &current_index,
                                    encoding, &result, &result_len);
        if (r != MAILIMF_NO_ERROR) {
            mailmime_decoded_part_free(result);
            self.lastError = MailCoreCreateError(r, @"Error parsing the message");
            return NO;
        }
        NSData *data = [NSData dataWithBytes:result length:result_len];
        mailmessage_fetch_result_free(mMessage, fetchedData);
        mailmime_decoded_part_free(result);
        mailmime_single_fields_free(mimeFields);
        self.data = data;
        self.fetched = YES;
    }
    return YES;
}

- (BOOL)fetchPart {
    return [self fetchPartWithProgress:^(size_t curr, size_t max){}];
}

- (struct mailmime *)buildMIMEStruct {
    struct mailmime_fields *mime_fields;
    struct mailmime *mime_sub;
    struct mailmime_content *content;
    struct mailmime_parameter * param;
    int r;

    if (mFilename) {
        char *charData = (char *)[mFilename cStringUsingEncoding:NSUTF8StringEncoding];
        char *dupeData = malloc(strlen(charData) + 1);
        strcpy(dupeData, charData);
        mime_fields = mailmime_fields_new_filename( MAILMIME_DISPOSITION_TYPE_ATTACHMENT, 
                                                    dupeData,
                                                    MAILMIME_MECHANISM_BASE64 ); 
    } else {
        mime_fields = mailmime_fields_new_encoding(MAILMIME_MECHANISM_BASE64);
    }
    if (self.contentId) {
        struct mailmime_field*  contentId= mailmime_field_new(MAILMIME_FIELD_ID, NULL, NULL, strdup([self.contentId UTF8String]), NULL, 0, NULL, NULL, NULL);
        mailmime_fields_add(mime_fields, contentId);
    }
    content = mailmime_content_new_with_str([self.contentType cStringUsingEncoding:NSUTF8StringEncoding]);
    mime_sub = mailmime_new_empty(content, mime_fields);
    param = mailmime_parameter_new(strdup("charset"), strdup(DEST_CHARSET));
    r = clist_append(content->ct_parameters, param);
    param = mailmime_parameter_new(strdup("name"), strdup([mFilename cStringUsingEncoding:NSUTF8StringEncoding]));
    r = clist_append(content->ct_parameters, param);

    // Add Data
    r = mailmime_set_body_text(mime_sub, (char *)[self.data bytes], [self.data length]);
    return mime_sub;
}

- (size_t)size {
    if (mMime) {
        return mMime->mm_length;
    }
    return 0;
}

- (struct mailmime_single_fields *)mimeFields {
    return mMimeFields;
}

- (void)dealloc {
    mailmime_single_fields_free(mMimeFields);
    [mData release];
    [mFilename release];
    [mContentId release];
    self.lastError = nil;
    //The structs are held by CTCoreMessage so we don't have to free them
    [super dealloc];
}
@end
