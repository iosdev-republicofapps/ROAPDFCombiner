//
//  ROAPDFCombiner.h
//  ROAPDFCombiner
//
//  Created by RepublicOfApps, LLC on 1/3/15.
//  Copyright (c) 2015 RepublicOfApps, LLC. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <Quartz/Quartz.h>


#pragma mark - Constants

extern NSString * const kROAPDFCombinerErrorDomain;
typedef NS_ENUM(NSInteger, ROAPDFCombinerErrorCode) {
    ROAPDFCombinerErrorCodeNoSources,
    ROAPDFCombinerErrorCodeInvalidSourceContent,
    ROAPDFCombinerErrorCodeInvalidPDFData,
    ROAPDFCombinerErrorCodeFilePathCannotBeRead,
    ROAPDFCombinerErrorCodeFilePathDoesNotResolveToAValidFileURL,
    ROAPDFCombinerErrorCodeURLCannotBeDownloaded,
    ROAPDFCombinerErrorCodeInvalidSourceRange,
    ROAPDFCombinerErrorCodeUnknown
};


#pragma mark - ROAPDFCombiner

@interface ROAPDFCombiner : NSObject

+ (void)combineSources:(NSArray *)sources
               success:(void (^)(PDFDocument *combinedDocument))success
             failure:(void (^)(NSError *error))failure;

@end


#pragma mark - ROAPDFDocumentSource

/**
 The source of a single PDFDocument and the range of pages from that document
 to be combined with other sources during combination.
 
 Think of this as a handle to a PDFDocument that may hold the
 document or its data directly or be an external link to the document as a file.
 
 It also stores the range of pages to use from the document during combination,
 in case you don't want to combine the whole document.
 
 If you need to combine multiple non-contiguous page ranges from a given document,
 you may include the document as multiple sources, one per range.  The combiner will
 notice that you've included the document more than once and cache it efficiently.
 */
@interface ROAPDFDocumentSource : NSObject

#pragma mark - Properties

/**
 The content of a single PDF Document.
 
 May be any one of:
 
 # A PDFDocument
 in which case the document is used directly.
 
 # An NSData representation of a PDFDocument
 in which case a PDFDocument is constructed from the data.
 
 # An NSString file path of a PDFDocument
 in which case a PDFDocument is read from the file at the given path.
 
 # An NSURL of a PDFDocument
 in which case a PDFDocument is read (from a file url) or fetched (from a remote url).
 */
@property (nonatomic, readonly) NSObject *content;

/**
 The first page from the content to use during combining.
 Pages are numbered from 0.
 If this value is nil, startPage will be considered 0
 and all pages <= endPage will be used.
 */
@property (nonatomic, readonly) NSNumber *startPage;

/**
 The last page from the content to use during combining.
 Pages are numbered from 0.
 If this value is nil, all pages >= startPage will be used.
 If non-nil, this value must be >= startPage.
 */
@property (nonatomic, readonly) NSNumber *endPage;

#pragma mark - Initializers

- (instancetype)initWithContent:(NSObject *)content startPage:(NSNumber *)startPage endPage:(NSNumber *)endPage;

@end
