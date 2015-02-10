//
//  ROAPDFCombiner.m
//  ROAPDFCombiner
//
//  Created by RepublicOfApps, LLC on 1/3/15.
//  Copyright (c) 2015 RepublicOfApps, LLC. All rights reserved.
//

#import "ROAPDFCombiner.h"


#pragma mark - Constants

NSString * const kROAPDFCombinerErrorDomain = @"com.republicofapps.ROAPDFCombinerErrorDomain";


#pragma mark - ROAPDFCombiner

@implementation ROAPDFCombiner

#pragma mark - Public API

+ (void)combineSources:(NSArray *)sources
               success:(void (^)(PDFDocument *combinedDocument))success
               failure:(void (^)(NSError *error))failure
{
    if ([sources count] == 0) {
        if (failure) {
            NSError *error = [self errorWithCode:ROAPDFCombinerErrorCodeNoSources];
            dispatch_async(dispatch_get_main_queue(), ^{
                failure(error);
            });
        }
        
        return;
    }
    
    NSMutableDictionary *ordinalToFetched = [NSMutableDictionary dictionaryWithCapacity:[sources count]];

    NSString *fetchQueueLabel   = [NSString stringWithFormat:@"com.republicofapps.ROAPDFCombiner_Fetch_%@", [NSUUID UUID].UUIDString];
    dispatch_queue_t fetchQueue = dispatch_queue_create([fetchQueueLabel UTF8String], DISPATCH_QUEUE_CONCURRENT);

    NSString *storeQueueLabel   = [NSString stringWithFormat:@"com.republicofapps.ROAPDFCombiner_Store_%@", [NSUUID UUID].UUIDString];
    dispatch_queue_t storeQueue = dispatch_queue_create([storeQueueLabel UTF8String], DISPATCH_QUEUE_SERIAL);

    NSString *combineQueueLabel   = [NSString stringWithFormat:@"com.republicofapps.ROAPDFCombiner_Combine_%@", [NSUUID UUID].UUIDString];
    dispatch_queue_t combineQueue = dispatch_queue_create([combineQueueLabel UTF8String], DISPATCH_QUEUE_SERIAL);
    
    dispatch_group_t commonGroup = dispatch_group_create();
    
    /*
     * Fetch and store documents.
     */
    
    for (NSUInteger ordinal = 0; ordinal < [sources count]; ++ordinal) {
        ROAPDFDocumentSource *source = sources[ordinal];

        dispatch_group_async(commonGroup, fetchQueue, ^{
            // Fetch
            NSError * __autoreleasing error = nil;
            PDFDocument *document = [self fetchDocumentFromSource:source withError:&error];
            
            NSError * __strong strongError = error;
            
            // Store
            dispatch_group_async(commonGroup, storeQueue, ^{
                if (document) {
                    ordinalToFetched[@(ordinal)] = document;
                } else if (strongError) {
                    ordinalToFetched[@(ordinal)] = strongError;
                }
            });
        });
    }
    
    /*
     * Combine documents.
     */
    
    dispatch_group_notify(commonGroup, combineQueue, ^{
        NSMutableArray *documents = [NSMutableArray arrayWithCapacity:[sources count]];
        NSNumber *firstNonDocumentOrdinal = nil;
        for (NSUInteger ordinal = 0; ordinal < [sources count]; ++ordinal) {
            NSObject *document = ordinalToFetched[@(ordinal)];
            if ([document isKindOfClass:[PDFDocument class]]) {
                [documents addObject:document];
            } else {
                if (!firstNonDocumentOrdinal) {
                    firstNonDocumentOrdinal = @(ordinal);
                }
                [documents addObject:document ? document : [NSNull null]];
            }
        }
        
        if (firstNonDocumentOrdinal) {
            if (failure) {
                NSError *error;
                NSObject *nonDocument = documents[[firstNonDocumentOrdinal unsignedIntegerValue]];
                if ([nonDocument isKindOfClass:[NSError class]]) {
                    error = (NSError *)nonDocument;
                } else {
                    error = [self errorWithCode:ROAPDFCombinerErrorCodeUnknown];
                }

                dispatch_async(dispatch_get_main_queue(), ^{
                    failure((NSError *)nonDocument);
                });
            }
        } else {
            dispatch_async(combineQueue, ^{
                [self combineSources:sources
                           documents:documents
                             success:success
                             failure:failure];
            });
        }
    });
}

#pragma mark - Private API: Fetch Documents

+ (PDFDocument *)fetchDocumentFromSource:(ROAPDFDocumentSource *)source withError:(NSError * __autoreleasing *)error
{
    if ([source.content isKindOfClass:[PDFDocument class]]) {
        return [self fetchDocumentFromSourceDocument:source withError:error];
    } else if ([source.content isKindOfClass:[NSData class]]) {
        return [self fetchDocumentFromSourceData:source withError:error];
    } else if ([source.content isKindOfClass:[NSString class]]) {
        return [self fetchDocumentFromSourceString:source withError:error];
    } else if ([source.content isKindOfClass:[NSURL class]]) {
        return [self fetchDocumentFromSourceURL:source withError:error];
    } else {
        return nil;
    }
}

+ (PDFDocument *)fetchDocumentFromSourceDocument:(ROAPDFDocumentSource *)sourceDocument withError:(NSError * __autoreleasing *)error
{
    NSAssert([sourceDocument.content isKindOfClass:[PDFDocument class]], @"Expected sourceDocument.content to be a PDFDocument object.");
    return (PDFDocument *)sourceDocument.content;
}

+ (PDFDocument *)fetchDocumentFromSourceData:(ROAPDFDocumentSource *)sourceData withError:(NSError * __autoreleasing *)error
{
    NSAssert([sourceData.content isKindOfClass:[NSData class]], @"Expected sourceData.content to be an NSData object.");
    PDFDocument *document = [[PDFDocument alloc] initWithData:(NSData *)sourceData.content];
    if (!document && error) {
        *error = [self errorWithCode:ROAPDFCombinerErrorCodeInvalidPDFData];
    }
    return document;
}

+ (PDFDocument *)fetchDocumentFromSourceString:(ROAPDFDocumentSource *)sourceString withError:(NSError * __autoreleasing *)error
{
    NSAssert([sourceString.content isKindOfClass:[NSString class]], @"Expected sourceString.content to be an NSString object.");
    NSURL *url = [NSURL URLWithString:(NSString *)sourceString.content];
    if (!url) {
        if (error) {
            *error = [self errorWithCode:ROAPDFCombinerErrorCodeFilePathDoesNotResolveToAValidFileURL];
        }
        return nil;
    } else {
        PDFDocument *document = [self fetchDocumentFromURL:url];
        if (!document && error) {
            *error = [self errorWithCode:ROAPDFCombinerErrorCodeFilePathCannotBeRead];
        }
        return document;
    }
}

+ (PDFDocument *)fetchDocumentFromSourceURL:(ROAPDFDocumentSource *)sourceURL withError:(NSError * __autoreleasing *)error
{
    NSAssert([sourceURL.content isKindOfClass:[NSURL class]], @"Expected sourceURL.content to be an NSURL object.");
    PDFDocument *document = [self fetchDocumentFromURL:(NSURL *)sourceURL];
    if (!document && error) {
        *error = [self errorWithCode:ROAPDFCombinerErrorCodeURLCannotBeDownloaded];
    }
    return document;
}

+ (PDFDocument *)fetchDocumentFromURL:(NSURL *)url
{
    return [[PDFDocument alloc] initWithURL:url];
}

#pragma mark - Private API: Combine Documents

+ (void)combineSources:(NSArray *)sources
                     documents:(NSArray *)documents
                       success:(void (^)(PDFDocument *combinedDocument))success
                       failure:(void (^)(NSError *error))failure
{
    NSAssert2([sources count] == [documents count], @"sources count %lu does not agree with documents count %lu", (unsigned long)[sources count], (unsigned long)[documents count]);
    
    PDFDocument *combinedDocument = [[PDFDocument alloc] init];
    for (NSUInteger ordinal = 0; ordinal < [sources count]; ++ordinal) {
        ROAPDFDocumentSource *source = [sources objectAtIndex:ordinal];
        PDFDocument *sourceDocument = [documents objectAtIndex:ordinal];
        
        NSInteger startPage = [source.startPage integerValue];
        NSInteger endPage;
        if (source.endPage) {
            endPage = [source.endPage integerValue];
        } else {
            if (sourceDocument.pageCount > 0) {
                endPage = sourceDocument.pageCount - 1;
            } else {
                endPage = 0;
            }
        }
        
        if (startPage < 0 || startPage >= sourceDocument.pageCount || endPage < startPage || endPage >= sourceDocument.pageCount) {
            if (failure) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    NSError *error = [self errorWithCode:ROAPDFCombinerErrorCodeInvalidSourceRange];
                    failure(error);
                });
                return;
            }
        }
        
        if (sourceDocument.pageCount == 0) {
            // Nothing do combine
            continue;
        }
        
        for (NSUInteger pageOrdinal = startPage; pageOrdinal <= endPage; ++pageOrdinal) {
            PDFPage *page = [sourceDocument pageAtIndex:pageOrdinal];
            // The Apple comments in PDFDocument.h concerning insertPage:atIndex: indicate
            // it's safest to insert a copy of a page across documents to avoid messing with
            // the page's owning document reference.
            [combinedDocument insertPage:[page copy] atIndex:combinedDocument.pageCount];
        }
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        if (success) {
            success(combinedDocument);
        }
    });
}

#pragma mark - Private API: NSError Management

+ (NSError *)errorWithCode:(ROAPDFCombinerErrorCode)code
{
    return [NSError errorWithDomain:kROAPDFCombinerErrorDomain
                               code:code
                           userInfo:@{
                                      NSLocalizedDescriptionKey : [self errorLocalizedDescriptionForDomain:kROAPDFCombinerErrorDomain
                                                                                                      code:code]
                                      }];
}

+ (NSString *)errorLocalizedDescriptionForDomain:(NSString *)domain code:(ROAPDFCombinerErrorCode)code
{
    NSString *reason = nil;
    switch (code) {
        case ROAPDFCombinerErrorCodeNoSources:
            reason = @"no sources were specified";
            break;
        case ROAPDFCombinerErrorCodeInvalidSourceContent:
            reason = @"the source content was not of a valid type";
            break;
        case ROAPDFCombinerErrorCodeInvalidPDFData:
            reason = @"the source content was not a valid PDFDocument data representation";
            break;
        case ROAPDFCombinerErrorCodeFilePathCannotBeRead:
            reason = @"the source file path does not exist or does not represent a valid PDFDocument";
            break;
        case ROAPDFCombinerErrorCodeFilePathDoesNotResolveToAValidFileURL:
            reason = @"the source file path cannot be resolved to a valid file URL";
            break;
        case ROAPDFCombinerErrorCodeURLCannotBeDownloaded:
            reason = @"the source URL does not exist or does not represent a valid PDFDocument";
            break;
        case ROAPDFCombinerErrorCodeInvalidSourceRange:
            reason = @"the source range is invalid: either the range is not a valid range or the document does not contain all pages in the range";
            break;
        case ROAPDFCombinerErrorCodeUnknown:
        default:
            reason = @"an unknown error occurred";
            break;
    }
    
    return [NSString stringWithFormat:@"An error in domain %@ with code %ld occurred: %@.", domain, code, reason];
}

@end


#pragma mark - ROAPDFDocumentSource

@implementation ROAPDFDocumentSource

#pragma mark - Initializers

- (instancetype)initWithContent:(NSObject *)content startPage:(NSNumber *)startPage endPage:(NSNumber *)endPage
{
    if ((self = [super init])) {
        _content   = content;
        _startPage = startPage;
        _endPage   = endPage;
    }
    return self;
}

- (instancetype)init
{
    return [self initWithContent:nil startPage:nil endPage:nil];
}

#pragma mark - NSObject Overrides

- (NSString *)description
{
    NSString *contentDescription;
    if ([self.content isKindOfClass:[PDFDocument class]]) {
        contentDescription = [NSString stringWithFormat:@"{PDFDocument: %@}", self.content];
    } else if ([self.content isKindOfClass:[NSData class]]) {
        contentDescription = [NSString stringWithFormat:@"{NSData: %lu bytes}", [(NSData *)self.content length]];
    } else if ([self.content isKindOfClass:[NSString class]]) {
        contentDescription = [NSString stringWithFormat:@"{NSString: %@}", self.content];
    } else if ([self.content isKindOfClass:[NSURL class]]) {
        contentDescription = [NSString stringWithFormat:@"{NSURL: %@}", self.content];
    } else {
        contentDescription = [NSString stringWithFormat:@"{Unknown: %@}", self.content];
    }
    
    return [NSString stringWithFormat:@"{ROAPDFDocumentSource: content=%@, startPage=%@, endPage=%@}", contentDescription, self.startPage, self.endPage];
}

@end
