/*
 * iSENSE Project - isenseproject.org
 * This file is part of the iSENSE iOS API and applications.
 *
 * Copyright (c) 2015, University of Massachusetts Lowell. All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * Redistributions of source code must retain the above copyright notice, this
 * list of conditions and the following disclaimer. Redistributions in binary
 * form must reproduce the above copyright notice, this list of conditions and
 * the following disclaimer in the documentation and/or other materials
 * provided with the distribution. Neither the name of the University of
 * Massachusetts Lowell nor the names of its contributors may be used to
 * endorse or promote products derived from this software without specific
 * prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
 * AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL THE REGENTS OR CONTRIBUTORS BE LIABLE FOR
 * ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
 * DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
 * SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
 * CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
 * LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
 * OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH
 * DAMAGE.
 *
 * BSD 3-Clause License
 * http://opensource.org/licenses/BSD-3-Clause
 *
 * Our work is supported by grants DRL-0735597, DRL-0735592, DRL-0546513, IIS-1123998,
 * and IIS-1123972 from the National Science Foundation and a gift from Google Inc.
 *
 */

//
// API.m
// iSENSE_API
//
// Created by Jeremy Poulin on 8/21/13.
//

#import "API.h"

@implementation API

#define LIVE_URL @"https://isenseproject.org/api/v1"
#define DEV_URL  @"http://rsense-dev.cs.uml.edu/api/v1"

#define GET_REQUEST     @"GET"
#define POST_REQUEST    @"POST"
#define PUT_REQUEST     @"PUT"
#define DELETE_REQUEST  @"DELETE"
#define NONE            @""

#define BOUNDARY @"*****"

static NSString *baseUrl, *authenticityToken;
static RPerson *currentUser;
static NSString *currentContribKey;
static NSString *email, *password;

/**
 * Access the current instance of an API object.
 *
 * @return An instance of the API object
 */
+ (id)getInstance {
    static API *api = nil;
    static dispatch_once_t initApi;
    dispatch_once(&initApi, ^{
        api = [[self alloc] init];
    });
    return api;
}

/*
 * Initializes all the static variables in the API.
 *
 * @return The current instance of the API
 */
- (id)init {
    if (self = [super init]) {
        baseUrl = LIVE_URL;
        authenticityToken = nil;
        currentUser = nil;
        currentContribKey = @"";
    }
    return self;
}

/**
 * Change the baseUrl directly.
 *
 * @param newUrl NSString version of the URL you want to use.
 */
- (void)setBaseUrl:(NSString *)newUrl {
    baseUrl = newUrl;
}

/**
 * The ever important switch between live iSENSE and our development site.
 *
 * @param useDev Set to true if you want to use the development site.
 */
- (void)useDev:(BOOL)useDev {
	if (useDev) {
		baseUrl = DEV_URL;
	} else {
		baseUrl = LIVE_URL;
	}
}

/**
 * Returns whether the API is currently set to dev mode
 */
- (BOOL)isUsingDev {
    return ([baseUrl isEqualToString:DEV_URL]);
}

/**
 * Checks for connectivity using Apple's reachability class.
 *
 * @return YES if you have connectivity, NO if it does not
 */
+ (BOOL)hasConnectivity {
    Reachability *reachability = [Reachability reachabilityForInternetConnection];
    NetworkStatus networkStatus = [reachability currentReachabilityStatus];
    return !(networkStatus == NotReachable);
}

/**
 * Log in to iSENSE. After calling this function, if success is returned, authenticated API functions will work properly.
 *
 * @param username The username of the user to log in as
 * @param password The password of the user to log in as
 * @return TRUE if login succeeds, FALSE if it does not
 */
- (RPerson *)createSessionWithEmail:(NSString *)p_email andPassword:(NSString *)p_password {

    if (p_email == nil || p_password == nil || ![p_email length] || ![p_password length]) {
        return nil;
    }

    // if coming from the Keychain, the password may be of NSData type instead of NSString -
    // if so, convert it
    NSString *decode_pass = p_password;
    if ([p_password isKindOfClass:[NSData class]]) {
        decode_pass = [[NSString alloc] initWithData:((NSData *)p_password) encoding:NSUTF8StringEncoding];
    }

    NSString *parameters = [@"email=" stringByAppendingString:
                            [p_email stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]];
    parameters = [parameters stringByAppendingString:
                  [@"&password=" stringByAppendingString:
                   [decode_pass stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding]]];

    NSDictionary *result = [self makeRequestWithBaseUrl:baseUrl withPath:@"users/myInfo" withParameters:parameters withRequestType:GET_REQUEST andPostData:nil];

    email = p_email;
    password = decode_pass;
    
    if ([result objectForKey:@"name"] != nil) {

        email = p_email;
        password = decode_pass;
        RPerson *you = [[RPerson alloc] init];
        you.name = [result objectForKey:@"name"];
        you.gravatar = [result objectForKey:@"gravatar"];
        /* iSENSE doesn't use HTTPS for Gravatar; we ought to use it here... */
        you.gravatar = [you.gravatar stringByReplacingOccurrencesOfString:@"http"
                                             withString:@"https"];
        
        NSURL *imageURL = [NSURL URLWithString:[you gravatar]];
        NSData *imageData = [NSData dataWithContentsOfURL:imageURL];
        you.gravatarImage = [UIImage imageWithData:imageData];

        [self saveCurrentUserToKeychain];

        currentUser = you;
        return you;
    } else {
        return nil;
    }
}

/**
 * Log out of iSENSE.
 */
- (void)deleteSession {
    
    email = @"";
    password = @"";
    currentUser = nil;

    [self clearCurrentUserFromKeychain];
}

/**
 * Retrieves information about a single project on iSENSE.
 *
 * @param projectId The ID of the project to retrieve
 * @return An RProject object
 */
- (RProject *)getProjectWithId:(int)projectId {
    
    RProject *proj = [[RProject alloc] init];
    
    NSString *path = [NSString stringWithFormat:@"projects/%d", projectId];
    NSDictionary *results = [self makeRequestWithBaseUrl:baseUrl withPath:path withParameters:NONE withRequestType:GET_REQUEST andPostData:nil];
    
    proj.project_id = [results objectForKey:@"id"];
    proj.name = [results objectForKey:@"name"];
    proj.url = [results objectForKey:@"url"];
    proj.hidden = [results objectForKey:@"hidden"];
    proj.featured = [results objectForKey:@"featured"];
    proj.like_count = [results objectForKey:@"likeCount"];
    proj.timecreated = [results objectForKey:@"createdAt"];
    proj.owner_name = [results objectForKey:@"ownerName"];
    proj.owner_url = [results objectForKey:@"ownerUrl"];
    
    return proj;
    
}

/**
 * Retrieve a data set from iSENSE, with it's data field filled in.
 * The internal data set will be converted to column-major format, to make it compatible with
 * the uploadDataSet function
 *
 * @param dataSetId The unique ID of the data set to retrieve from iSENSE
 * @return An RDataSet object
 */
- (RDataSet *)getDataSetWithId:(int)dataSetId {
    RDataSet *dataSet = [[RDataSet alloc] init];
    
    NSDictionary *results = [self makeRequestWithBaseUrl:baseUrl withPath:[NSString stringWithFormat:@"data_sets/%d", dataSetId] withParameters:@"recur=true" withRequestType:GET_REQUEST andPostData:nil];
    
    dataSet.ds_id = [results objectForKey:@"id"];
    dataSet.name = [results objectForKey:@"name"];
    dataSet.hidden = [results objectForKey:@"hidden"];
    dataSet.url = [results objectForKey:@"url"];
    dataSet.timecreated = [results objectForKey:@"createdAt"];
    dataSet.fieldCount = [results objectForKey:@"fieldCount"];
    dataSet.datapointCount = [results objectForKey:@"datapointCount"];
    dataSet.project_id = [[results objectForKey:@"project"] objectForKey:@"id"];
    
    NSArray *dataArray = [results objectForKey:@"data"];
    NSMutableDictionary *dataObject = [[NSMutableDictionary alloc] init];
    [dataObject setObject:dataArray forKey:@"data"];
    dataSet.data = [self rowsToCols:dataObject];

    return dataSet;
}

/**
 * Gets all of the fields associated with a project.
 *
 * @param projectId The unique ID of the project whose fields you want to see
 * @return An ArrayList of RProjectField objects
 */
- (NSArray *)getProjectFieldsWithId:(int)projectId {
    NSMutableArray *fields = [[NSMutableArray alloc] init];
    
    NSDictionary *requestResult = [self makeRequestWithBaseUrl:baseUrl withPath:[NSString stringWithFormat:@"projects/%d", projectId] withParameters:@"recur=false" withRequestType:GET_REQUEST andPostData:nil];
    NSArray *innerFields = [requestResult objectForKey:@"fields"];
    
    for (int i = 0; i < innerFields.count; i++) {
        NSDictionary *innermostField = [innerFields objectAtIndex:i];
        RProjectField *newProjField = [[RProjectField alloc]
                                       initWithName:[innermostField objectForKey:@"name"]
                                       type:[innermostField objectForKey:@"type"]
                                       unit:[innermostField objectForKey:@"unit"]
                                       andRestrictions:[innermostField objectForKey:@"restrictions"]];
        
        newProjField.field_id = [innermostField objectForKey:@"id"];

        [fields addObject:newProjField];
    }
    
    return fields;
}

/**
 * Gets all the data sets associated with a project
 * The data sets returned by this function do not have their data field filled.
 *
 * @param projectId The project ID whose data sets you want
 * @return An ArrayList of RDataSet objects, with their data fields left null
 */
- (NSArray *)getDataSetsWithId:(int)projectId {
    NSMutableArray *dataSets = [[NSMutableArray alloc] init];
    
    NSDictionary *results = [self makeRequestWithBaseUrl:baseUrl withPath:[NSString stringWithFormat:@"projects/%d", projectId] withParameters:@"recur=true" withRequestType:GET_REQUEST andPostData:nil];
    NSArray *resultsArray = [results objectForKey:@"dataSets"];
    for (int i = 0; i < [[results objectForKey:@"dataSetCount"] integerValue]; i++) {
        RDataSet *dataSet = [[RDataSet alloc] init];
        NSDictionary *innermost = [resultsArray objectAtIndex:i];
        
        dataSet.ds_id = [innermost objectForKey:@"id"];
        dataSet.name = [innermost objectForKey:@"name"];
        dataSet.hidden = [innermost objectForKey:@"hidden"];
        dataSet.url = [innermost objectForKey:@"url"];
        dataSet.timecreated = [innermost objectForKey:@"createdAt"];
        dataSet.fieldCount = [innermost objectForKey:@"fieldCount"];
        dataSet.datapointCount = [innermost objectForKey:@"datapointCount"];
        
        [dataSets addObject:dataSet];
    }
    
    return dataSets;
}

/**
 * 	Retrieves multiple projects off of iSENSE.
 *
 * @param page Which page of results to start from. 1-indexed
 * @param perPage How many results to display per page
 * @param sort Accepts a SortType enum
 * @param search A string to search all projects for
 * @return An ArrayList of RProject objects
 */
- (NSArray *)getProjectsAtPage:(int)page withPageLimit:(int)perPage withFilter:(SortType)sort andQuery:(NSString *)search {
    NSMutableArray *results = [[NSMutableArray alloc] init];

    NSString *sortMode = [[NSString alloc] init];
    NSString *order = [[NSString alloc] init];
    switch (sort) {
        case CREATED_AT_DESC:
            sortMode = @"created_at";
            order = @"DESC";
            break;
        case CREATED_AT_ASC:
            sortMode = @"created_at";
            order = @"ASC";
            break;
        case UPDATED_AT_DESC:
            sortMode = @"updated_at";
            order = @"DESC";
            break;
        case UPDATED_AT_ASC:
            sortMode = @"updated_at";
            order = @"ASC";
            break;
    }

    NSString *parameters = [NSString stringWithFormat:@"page=%d&per_page=%d&sort=%s&order=%s&search=%s",
                            page, perPage, sortMode.UTF8String, order.UTF8String, search.UTF8String];

    NSArray *reqResult = [self makeRequestWithBaseUrl:baseUrl withPath:@"projects" withParameters:parameters withRequestType:GET_REQUEST andPostData:nil];

    // if no projects come back, return an empty array
    if (!reqResult) {
        return results;
    }

    for (NSDictionary *innerProjJSON in reqResult) {
        RProject *proj = [[RProject alloc] init];
        
        proj.project_id = [innerProjJSON objectForKey:@"id"];
        proj.name = [innerProjJSON objectForKey:@"name"];
        proj.url = [innerProjJSON objectForKey:@"url"];
        proj.hidden = [innerProjJSON objectForKey:@"hidden"];
        proj.featured = [innerProjJSON objectForKey:@"featured"];
        proj.like_count = [innerProjJSON objectForKey:@"likeCount"];
        proj.timecreated = [innerProjJSON objectForKey:@"createdAt"];
        proj.owner_name = [innerProjJSON objectForKey:@"ownerName"];
        proj.owner_url = [innerProjJSON objectForKey:@"ownerUrl"];
        
        [results addObject:proj];
        
    }
    
    return results;
    
}

/*
 * Returns the current saved user object.
 *
 * @return An RPerson object that corresponds to the owner of the current session
 */
- (RPerson *)getCurrentUser {
    return currentUser;
}

/**
 * Creates a new project on iSENSE. The Field objects in the second parameter must have
 * at a type and a name, and can optionally have a unit. This is an authenticated function.
 *
 * @param name The name of the new project to be created
 * @param fields An ArrayList of field objects that will become the fields on iSENSE.
 * @return The ID of the created project
 */
- (int)createProjectWithName:(NSString *)name andFields:(NSArray *)fields {
    
    @try {
        NSMutableDictionary *postData = [[NSMutableDictionary alloc] init];
        [postData setObject:[NSString stringWithFormat:@"%@",email] forKey:@"email"];
        [postData setObject:[NSString stringWithFormat:@"%@",password] forKey:@"password"];
        [postData setObject:[NSString stringWithFormat:@"%@",name] forKey:@"project_name"];
        
        NSError *error;
        NSData *postReqData = [NSJSONSerialization dataWithJSONObject:postData
                                                              options:0
                                                                error:&error];
        if (error) {
            NSLog(@"Error parsing object to JSON: %@", error);
        }
        
        NSDictionary *requestResult = [self makeRequestWithBaseUrl:baseUrl withPath:@"projects" withParameters:NONE withRequestType:POST_REQUEST andPostData:postReqData];
        
        NSNumber *projectId = [requestResult objectForKey:@"id"];
        
        for (RProjectField *projField in fields) {
            NSMutableDictionary *fieldMetaData = [[NSMutableDictionary alloc] init];
            [fieldMetaData setObject:projectId forKey:@"project_id"];
            [fieldMetaData setObject:projField.type forKey:@"field_type"];
            [fieldMetaData setObject:projField.name forKey:@"name"];
            [fieldMetaData setObject:projField.unit forKey:@"unit"];
            
            NSMutableDictionary *fullFieldMeta = [[NSMutableDictionary alloc] init];
            [fullFieldMeta setObject:fieldMetaData forKey:@"field"];
            [fullFieldMeta setObject:[NSString stringWithFormat:@"%@",email] forKey:@"email"];
            [fullFieldMeta setObject:[NSString stringWithFormat:@"%@",password] forKey:@"password"];
            
            NSError *error;
            NSData *fieldPostReqData = [NSJSONSerialization dataWithJSONObject:fullFieldMeta
                                                                  options:0
                                                                    error:&error];
            if (error) {
                NSLog(@"Error parsing object to JSON: %@", error);
            }
            [self makeRequestWithBaseUrl:baseUrl withPath:@"fields" withParameters:NONE withRequestType:POST_REQUEST andPostData:fieldPostReqData];
        }
        
        return projectId.intValue;
    } @catch (NSException *e) {
        NSLog(@"%@", e);
    }
    
    return -1;
}

/**
 * Append new rows of data to the end of an existing data set.
 *
 * @param dataSetId The ID of the data set to append to
 * @param newData The new data to append
 *
 * @return true on success, false on failure
 */
- (bool)appendDataSetDataWithId:(int)dataSetId andData:(NSDictionary *)data {

    @try {
        NSMutableDictionary *requestData = [[NSMutableDictionary alloc] init];
        [requestData setObject:data forKey:@"data"];
        [requestData setObject:[NSString stringWithFormat:@"%d", dataSetId] forKey:@"id"];
        [requestData setObject:email forKey:@"email"];
        [requestData setObject:password forKey:@"password"];
        
        NSError *error;
        NSData *postReqData = [NSJSONSerialization dataWithJSONObject:requestData
                                                              options:0
                                                                error:&error];
        
        [self makeRequestWithBaseUrl:baseUrl withPath:@"data_sets/append" withParameters:NONE withRequestType:POST_REQUEST andPostData:postReqData];
        
        return true;
 
    }
    @catch (NSException *e) {
        NSLog(@"%@", e);
    }

    return false;
}

/**
 * Append new rows of data to the end of an existing data set with a contributor key.
 *
 * @param dataSetId The ID of the data set to append to
 * @param newData The new data to append
 *
 * @return true on success, false on failure
 */
- (bool)appendDataSetDataWithId:(int)dataSetId andData:(NSDictionary *)data withContributorKey:(NSString *)conKey{
    
    @try {
        NSMutableDictionary *requestData = [[NSMutableDictionary alloc] init];
        [requestData setObject:data forKey:@"data"];
        [requestData setObject:[NSString stringWithFormat:@"%d", dataSetId] forKey:@"id"];
        [requestData setObject:conKey forKey:@"contribution_key"];
        
        NSError *error;
        NSData *postReqData = [NSJSONSerialization dataWithJSONObject:requestData
                                                              options:0
                                                                error:&error];
        
        [self makeRequestWithBaseUrl:baseUrl withPath:@"data_sets/append" withParameters:NONE withRequestType:POST_REQUEST andPostData:postReqData];
        
        return true;

    }
    @catch (NSException *e) {
        NSLog(@"%@", e);
    }
    
    return false;
}

/**
 * Uploads a new data set to a project on iSENSE with a user logged in.
 *
 * @param projectId - The ID of the project to upload data to
 * @param dataToUpload - The data to be uploaded. Must be in column-major format to upload correctly
 * @param name - The name of the dataset
 * @return The integer ID of the newly uploaded dataset, or 0 if upload fails
 */
- (int) uploadDataToProject:(int)projectId withData:(NSDictionary *)dataToUpload andName:(NSString *)name {
    
    // append a timestamp to the name of the data set
    name = [NSString stringWithFormat:@"%@ - %@", name, [API getTimeStamp]];
    
    NSMutableDictionary *requestData = [[NSMutableDictionary alloc] init];
    
    [requestData setObject:dataToUpload forKey:@"data"];
    if (![name isEqualToString:NONE]) [requestData setObject:name forKey:@"title"];
    [requestData setObject:email forKey:@"email"];
    [requestData setObject:password forKey:@"password"];
    
    NSError *error;
    NSData *postReqData = [NSJSONSerialization dataWithJSONObject:requestData
                                                          options:0
                                                            error:&error];
    if (error) {
        NSLog(@"Error parsing object to JSON: %@", error);
    }
    
    NSDictionary *requestResult = [self makeRequestWithBaseUrl:baseUrl
                                                      withPath:[NSString stringWithFormat:@"projects/%d/jsonDataUpload", projectId]
                                                withParameters:NONE
                                               withRequestType:POST_REQUEST
                                                   andPostData:postReqData];
    
    NSNumber *dataSetId = [requestResult objectForKey:@"id"];
    return dataSetId.intValue;
}

/**
 * Uploads a new data set to a project on iSENSE with a contributor key.
 *
 * @param projectId - The ID of the project to upload data to
 * @param dataToUpload - The data to be uploaded. Must be in column-major format to upload correctly
 * @param conKey - contributor key
 * @param conName - Name of contributor
 * @return The integer ID of the newly uploaded dataset, or 0 if upload fails
 */
- (int) uploadDataToProject:(int)projectId withData:(NSDictionary *)dataToUpload withContributorKey:(NSString *)conKey as:(NSString *)conName andName:(NSString *)name{
    
    NSMutableDictionary *requestData = [[NSMutableDictionary alloc] init];
    
    name = [NSString stringWithFormat:@"%@ - %@", name, [API getTimeStamp]];
    
    [requestData setObject:name forKey:@"title"];
    [requestData setObject:conKey forKey:@"contribution_key"];
    [requestData setObject:conName forKey:@"contributor_name"];
    [requestData setObject:dataToUpload forKey:@"data"];
    
    NSError *error;
    NSData *postReqData = [NSJSONSerialization dataWithJSONObject:requestData
                                                          options:0
                                                            error:&error];
    if (error) {
        NSLog(@"Error parsing object to JSON: %@", error);
    }
    
    NSDictionary *requestResult = [self makeRequestWithBaseUrl:baseUrl
                                                      withPath:[NSString stringWithFormat:@"projects/%d/jsonDataUpload", projectId]
                                                withParameters:NONE
                                               withRequestType:POST_REQUEST
                                                   andPostData:postReqData];
    
    NSNumber *dataSetId = [requestResult objectForKey:@"id"];
    return dataSetId.intValue;
}


/*
 * Gets the MIME time from a file path.
 */
- (NSString *)getMimeType:(NSString *)path{
    
    CFStringRef pathExtension = (__bridge_retained CFStringRef)[path pathExtension];
    CFStringRef type = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, pathExtension, NULL);
    
    // The UTI can be converted to a mime type:
    NSString *mimeType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass(type, kUTTagClassMIMEType);
    
    return mimeType;
}

/**
 * Uploads a CSV file to iSENSE as a new data set.
 *
 * @param projectId The ID of the project to upload data to
 * @param csvToUpload The CSV as an NSData object
 * @param datasetName The name of the dataset
 * @return The ID of the data set created on iSENSE
 -(int)uploadCSVWithId:(int)projectId withFile:(NSData *)csvToUpload andName:(NSString *)name {
    
    // append a timestamp to the name of the data set
    name = [NSString stringWithFormat:@"%@ - %@", name, [self appendedTimeStamp]];
     
    // Make sure there aren't any illegal characters in the name
    name = [name stringByReplacingOccurrencesOfString:@" " withString:@"+"];

    // Tries to get the mime type of the specified file
    NSString *mimeType = [self getMimeType:name];
    
    // create request
    NSMutableURLRequest *request = [[NSMutableURLRequest alloc] init];
    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
    [request setHTTPShouldHandleCookies:YES];
    [request setTimeoutInterval:30];
    [request setHTTPMethod:POST_REQUEST];
    
    // set Content-Type in HTTP header
    NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", BOUNDARY];
    [request setValue:contentType forHTTPHeaderField: @"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    // post body
    NSMutableData *body = [NSMutableData data];
    
    // add image data
    if (csvToUpload) {
        [body appendData:[[NSString stringWithFormat:@"--%@\r\n", BOUNDARY] dataUsingEncoding:NSUTF8StringEncoding]];
        //[body appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"file\"; filename=\"%@\"\r\n", name] dataUsingEncoding:NSUTF8StringEncoding]];
       // [body appendData:[[NSString stringWithFormat:@"dataset_name: "]]];
        [body appendData:[[NSString stringWithFormat:@"Content-Type: %@\r\nContent-Transfer-Encoding: binary\r\n\r\n", mimeType] dataUsingEncoding:NSUTF8StringEncoding]];
        [body appendData:csvToUpload];
        [body appendData:[[NSString stringWithFormat:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]];
    }
    
    [body appendData:[[NSString stringWithFormat:@"--%@--\r\n", BOUNDARY] dataUsingEncoding:NSUTF8StringEncoding]];
    
    // setting the body of the post to the reqeust
    [request setHTTPBody:body];
    
    // set the content-length
    NSString *postLength = [NSString stringWithFormat:@"%lu", (unsigned long)[body length]];
    [request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    
    // set URL
    [request setURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@/projects/%d/CSVUpload?authenticity_token=%@", baseUrl, projectId, [self getEncodedAuthtoken]]]];
    NSLog(@"%@", request);
    
    // send request
    NSError *requestError;
    NSHTTPURLResponse *urlResponse;
    
    [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&requestError];
    if (requestError) {
        NSLog(@"Error received from server: %@", requestError);
        return -1;
    }
    
    return (int) [urlResponse statusCode];

}*/

/**
 * Uploads a file to the media section of a project.
 *
 * @param projectId The project ID to upload to
 * @param mediaToUpload The file to upload
 * @param name The name of the file to upload
 * @param ttype The upload target, PROJECT or DATASET
 * @return The media object ID for the media uploaded or -1 if upload fails
 */
- (int)uploadMediaToProject:(int)projectId withFile:(NSData *)mediaToUpload andName:(NSString *)name withTarget:(TargetType)ttype{
    
//    AFHTTPRequestSerializer *ser = [AFHTTPRequestSerializer serializer];
//    NSMutableURLRequest *request = [ser multipartFormRequestWithMethod:POST_REQUEST URLString:[baseUrl stringByAppendingString:@"/media_objects"] parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
//        [formData appendPartWithFileData:mediaToUpload name:@"upload" fileName:name mimeType:[self getMimeType:name]];
//        [formData appendPartWithFormData:[[email stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding] name:@"email"];
//        [formData appendPartWithFormData:[[password stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding] name:@"password"];
//        [formData appendPartWithFormData:[((ttype == PROJECT) ? @"project" : @"data_set") dataUsingEncoding:NSUTF8StringEncoding] name:@"type"];
//        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%d", projectId] dataUsingEncoding:NSUTF8StringEncoding] name:@"id"];
//    } error:nil];
//    
//    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
//    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
//    [request setHTTPShouldHandleCookies:YES];
//    [request setTimeoutInterval:30];
//    NSLog(@"%@", request);
//    
//    // send the request
//    NSError *requestError;
//    NSHTTPURLResponse *urlResponse;
//    
//    NSData *dataResponse = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&requestError];
//    if (requestError) NSLog(@"Error received from server: %@", requestError);
//    
//    if (urlResponse.statusCode >= 200 && urlResponse.statusCode < 300) {
//        id parsedJSONResponse = [NSJSONSerialization JSONObjectWithData:dataResponse options:NSJSONReadingMutableContainers error:&requestError];
//        int mediaObjectID = [parsedJSONResponse objectForKey:@"id"];
//        return mediaObjectID;
//    } else if (urlResponse.statusCode == 401) {
//        NSLog(@"Unauthorized. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    } else if (urlResponse.statusCode == 422) {
//        NSLog(@"Unprocessable entity. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    } else if (urlResponse.statusCode == 500) {
//        NSLog(@"Internal server error. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    } else {
//        NSLog(@"Unrecognized status code = %ld. %@", (long)urlResponse.statusCode, [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    }
//    
      return -1;
}

/**
 * Uploads a file to the media section of a project.
 *
 * @param projectId The project ID to upload to
 * @param mediaToUpload The file to upload
 * @param name The name of the file to upload
 * @param ttype The upload target, PROJECT or DATASET
 * @param conKey the contributor key used for upload
 * @param conName the name of the contributor
 * @return The media object ID for the media uploaded or -1 if upload fails
 */
- (int)uploadMediaToProject:(int)projectId withFile:(NSData *)mediaToUpload andName:(NSString *)name withTarget:(TargetType)ttype withContributorKey:(NSString *)conKey as:(NSString *)conName{
    
//    AFHTTPRequestSerializer *ser = [AFHTTPRequestSerializer serializer];
//    NSMutableURLRequest *request = [ser multipartFormRequestWithMethod:POST_REQUEST URLString:[baseUrl stringByAppendingString:@"/media_objects"] parameters:nil constructingBodyWithBlock:^(id<AFMultipartFormData> formData) {
//        [formData appendPartWithFileData:mediaToUpload name:@"upload" fileName:name mimeType:[self getMimeType:name]];
//        [formData appendPartWithFormData:[[conKey stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding] name:@"contribution_key"];
//        [formData appendPartWithFormData:[[conName stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding] dataUsingEncoding:NSUTF8StringEncoding] name:@"contributor_name"];
//        [formData appendPartWithFormData:[((ttype == PROJECT) ? @"project" : @"data_set") dataUsingEncoding:NSUTF8StringEncoding] name:@"type"];
//        [formData appendPartWithFormData:[[NSString stringWithFormat:@"%d", projectId] dataUsingEncoding:NSUTF8StringEncoding] name:@"id"];
//    } error:nil];
//    
//    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
//    [request setCachePolicy:NSURLRequestReloadIgnoringLocalCacheData];
//    [request setHTTPShouldHandleCookies:YES];
//    [request setTimeoutInterval:30];
//    NSLog(@"%@", request);
//    
//    // send the request
//    NSError *requestError;
//    NSHTTPURLResponse *urlResponse;
//    
//    NSData *dataResponse = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&requestError];
//    if (requestError) NSLog(@"Error received from server: %@", requestError);
//    
//    if (urlResponse.statusCode >= 200 && urlResponse.statusCode < 300) {
//        id parsedJSONResponse = [NSJSONSerialization JSONObjectWithData:dataResponse options:NSJSONReadingMutableContainers error:&requestError];
//        int mediaObjectID = [parsedJSONResponse objectForKey:@"id"];
//        return mediaObjectID;
//    } else if (urlResponse.statusCode == 401) {
//        NSLog(@"Unauthorized. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    } else if (urlResponse.statusCode == 422) {
//        NSLog(@"Unprocessable entity. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    } else if (urlResponse.statusCode == 500) {
//        NSLog(@"Internal server error. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    } else {
//        NSLog(@"Unrecognized status code = %ld. %@", (long)urlResponse.statusCode, [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
//    }
    
    return -1;
}


/**
 * Reformats a row-major NSDictionary to column-major.
 *
 * @param original The row-major formatted NSDictionary
 * @return A column-major reformatted version of the original NSDictionary
 */
- (NSDictionary *)rowsToCols:(NSDictionary *)original {
    NSMutableDictionary *reformatted = [[NSMutableDictionary alloc] init];
    NSArray *inner = [original objectForKey:@"data"];
    for(int i = 0; i < inner.count; i++) {
        NSDictionary *innermost = (NSDictionary *) [inner objectAtIndex:i];
        for (NSString *currKey in [innermost allKeys]) {
            NSMutableArray *currArray = nil;
            if(!(currArray = [reformatted objectForKey:currKey])) {
                currArray = [[NSMutableArray alloc] init];
            }
            [currArray addObject:[innermost objectForKey:currKey]];
            [reformatted setObject:currArray forKey:currKey];
        }
    }
    return reformatted;
}

/**
 * Makes an HTTP request for JSON-formatted data. Functions that
 * call this function should not be run on the UI thread.
 *
 * @param baseUrl The base of the URL to which the request will be made
 * @param path The path to append to the request URL
 * @param parameters Parameters separated by ampersands (&)
 * @param reqType The request type as a string (i.e. GET or POST)
 * @param postData The data to be given to iSENSE as NSData
 * @return An object dump of a JSONObject or JSONArray representing the requested data
 */
- (id)makeRequestWithBaseUrl:(NSString *)baseUrl withPath:(NSString *)path withParameters:(NSString *)parameters withRequestType:(NSString *)reqType andPostData:(NSData *)postData {

    parameters = [parameters stringByAddingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
    
    NSURL *url = [[NSURL alloc] initWithString:[NSString stringWithFormat:@"%@/%@?%@", baseUrl, path, parameters]];

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestReloadIgnoringLocalAndRemoteCacheData
                                                       timeoutInterval:10];
    [request setHTTPMethod:reqType];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];
    
    if (postData) {
        [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
        [request setValue:[NSString stringWithFormat:@"%lu", (unsigned long)postData.length] forHTTPHeaderField:@"Content-Length"];
        [request setHTTPBody:postData];
        
        NSString *LOG_STR = [[NSString alloc] initWithData:postData encoding:NSUTF8StringEncoding];
        NSLog(@"API: posting data:\n%@", LOG_STR);
    }
    
    NSError *requestError;
    NSHTTPURLResponse *urlResponse;
    NSData *dataResponse;

    @try {
        dataResponse = [NSURLConnection sendSynchronousRequest:request returningResponse:&urlResponse error:&requestError];
    }
    @catch (NSException *exception) {
        // error caught is either stored in requestError or dataResponse will come back nil,
        // both of which are handled below
    }

    if (requestError || !dataResponse) {
        NSLog(@"Error received from server: %@", requestError);
        return nil;
    }

    if (urlResponse.statusCode >= 200 && urlResponse.statusCode < 300) {
        id parsedJSONResponse = [NSJSONSerialization JSONObjectWithData:dataResponse options:NSJSONReadingMutableContainers error:&requestError];
        return parsedJSONResponse;
    } else if (urlResponse.statusCode == 401) {
        NSLog(@"Unauthorized. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
    } else if (urlResponse.statusCode == 422) {
        NSLog(@"Unprocessable entity. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
    } else if (urlResponse.statusCode == 500) {
        NSLog(@"Internal server error. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
    } else if (urlResponse.statusCode == 404) {
        NSLog(@"Not found. %@", [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
    } else {
        NSLog(@"Unrecognized status code = %ld. %@", (long)urlResponse.statusCode, [[NSString alloc] initWithData:dataResponse encoding:NSUTF8StringEncoding]);
    }
    
    return nil;
}


/**
 * Creates a unique date and timestamp used to append to data sets uploaded to the iSENSE
 * website to ensure every data set has a unique identifier.
 *
 * @return A pretty formatted date and timestamp
 */
+ (NSString *)getTimeStamp {
    
    // get time and date
    NSDate *now = [NSDate date];
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateStyle:NSDateFormatterShortStyle];
    [formatter setTimeStyle:NSDateFormatterShortStyle];
    
    // get seconds and microseconds using c structs
    struct timeval time;
    gettimeofday(&time, NULL);
    int seconds = time.tv_sec % 60;
    int microseconds = time.tv_usec;
    NSString *secondStr = (seconds < 10) ? [NSString stringWithFormat:@"0%d", seconds] : [NSString stringWithFormat:@"%d", seconds];
    
    // format the timestamp
    NSString *rawTime = [formatter stringFromDate:now];
    NSArray *cmp = [rawTime componentsSeparatedByCharactersInSet:[NSCharacterSet characterSetWithCharactersInString:@" "]];
    
    [formatter setDateFormat:@"HH:mm"];
    rawTime = [formatter stringFromDate:now];
    
    NSString *timeStamp = [NSString stringWithFormat:@"%@ %@:%@.%d", cmp[0], rawTime, secondStr, microseconds];
    
    return timeStamp;
}

/**
 * Gets the current version of the production iSENSE website that this
 * API has been minimally confirmed to work for
 *
 * @return The version of iSENSE in MAJOR.MINOR version format
 */
- (NSString *)getVersion {
    return [NSString stringWithFormat:@"%@.%@", VERSION_MAJOR, VERSION_MINOR];
}

/**
 * Saves the current user, if one is logged in, to the Keychain
 * of the hosting application.
 */
- (void)saveCurrentUserToKeychain {

    KeychainItemWrapper *keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:KEYCHAIN_ID accessGroup:nil];
    [keychainItem setObject:password forKey:(__bridge id)(kSecValueData)];
    [keychainItem setObject:email forKey:(__bridge id)(kSecAttrAccount)];
}

/**
 * Retrieves the user saved in the Keychain, and if such a user
 * exists, attempts to login that user.
 *
 * @return true if a user was saved and logged in successfully, false otherwise
 */
- (bool)loadCurrentUserFromKeychain {

    KeychainItemWrapper *keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:KEYCHAIN_ID accessGroup:nil];
    NSString *key_pass = [keychainItem objectForKey:(__bridge id)(kSecValueData)];
    NSString *key_user = [keychainItem objectForKey:(__bridge id)(kSecAttrAccount)];

    if (key_pass && key_user) {
        if ([self createSessionWithEmail:key_user andPassword:key_pass]) {
            return true;
        }
    }

    return false;
}

/**
 * Called internally via the deleteSession function in the API, this method will
 * clear the Keychain for the current username and password
 */
- (void)clearCurrentUserFromKeychain {

    KeychainItemWrapper *keychainItem = [[KeychainItemWrapper alloc] initWithIdentifier:KEYCHAIN_ID accessGroup:nil];
    [keychainItem resetKeychainItem];
}

/**
 * Verifies whether a given contributor key exists for a given project
 *
 * @param conKey - The contributor key for the project
 * @param projectID - The project to test the contributor key with
 *
 * @return true if the contributor key is valid for the project, false otherwise
 */
- (bool) validateKey:(NSString *)conKey forProject:(int)projectID {

    // TODO this must be implemented in the web API first.  Once implemented,
    // the currentContribKey variable should only be set if it passes validation
    currentContribKey = conKey;
    return true;
}

/**
 * Returns the last validated contributor key to use for uploading
 */
- (NSString *)getCurrentContributorKey {
    return currentContribKey;
}

@end
