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
// ProjectBrowserViewController.m
// iSENSE_API
//
// Created by Jeremy Poulin on 1/31/14.
//

#import "ProjectBrowserViewController.h"

@interface ProjectBrowserViewController ()
@end

@implementation ProjectBrowserViewController

@synthesize bar, table, cell_count, isUpdating, projects, currentPage, currentQuery, delegate, spinnerDialog, projectsFiltered;

// pre-iOS6 rotating options
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    return YES;
}

// iOS6 rotating options
- (BOOL)shouldAutorotate {
    return YES;
}

// iOS6 interface orientations
- (UIInterfaceOrientationMask)supportedInterfaceOrientations {
    return UIInterfaceOrientationMaskAll;
}

// displays the correct xib based on orientation and device type - called automatically upon view controller entry
-(void) willRotateToInterfaceOrientation:(UIInterfaceOrientation)toInterfaceOrientation duration:(NSTimeInterval)duration {
    
    NSBundle *isenseBundle = [NSBundle bundleWithURL:[[NSBundle mainBundle] URLForResource:@"iSENSE_API_Bundle" withExtension:@"bundle"]];
    
    if([UIDevice currentDevice].userInterfaceIdiom==UIUserInterfaceIdiomPad) {

        [isenseBundle loadNibNamed:@"ProjectBrowserViewController_iPad"
                             owner:self
                           options:nil];
    } else {

        if (UIInterfaceOrientationIsLandscape(toInterfaceOrientation)) {

            [isenseBundle loadNibNamed:@"ProjectBrowserViewController~landscape_iPhone"
                                          owner:self
                                        options:nil];
        } else {

            [isenseBundle loadNibNamed:@"ProjectBrowserViewController_iPhone"
                                          owner:self
                                        options:nil];
        }
    }
}


- (id)initWithDelegate: (__weak id<ProjectBrowserDelegate>) delegateObject
{
    self = [super init];
    
    if (self) {
    
        delegate =  delegateObject;
        isenseAPI = [API getInstance];
        cell_count = 10;
        isUpdating = false;
    }

    return self;
}

- (void) viewDidAppear:(BOOL)animated {

    [super viewDidAppear:animated];
    [self willRotateToInterfaceOrientation:[[UIApplication sharedApplication] statusBarOrientation] duration:0];

    ISenseSearch *search = [[ISenseSearch alloc] init];
    self.tableView.tableHeaderView = bar;
    bar.delegate = self;
    
    [bar setShowsScopeBar:false];
    [bar setShowsCancelButton:false animated:true];
    [bar sizeToFit];
    
    spinnerDialog = [self getDispatchDialogWithMessage:@"Loading..."];
    [spinnerDialog show];

    [self updateProjects:search];
}

- (void)viewDidLoad {
    [super viewDidLoad];
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    [searchBar setShowsCancelButton:true animated:true];
    [searchBar sizeToFit];
}

/*
- (void)textFieldDidEndEditing:(UITextField *)textField {
    if ([textField.text isEqualToString:@""]) {
        [bar setShowsScopeBar:false];
    } else {
        [bar setShowsScopeBar:true];
    }
}
*/

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
}

// Default dispatch_async dialog with custom spinner
- (UIAlertView *) getDispatchDialogWithMessage:(NSString *)dString {

    UIAlertView *message = [[UIAlertView alloc] initWithTitle:dString
                                                      message:nil
                                                     delegate:self
                                            cancelButtonTitle:nil
                                            otherButtonTitles:nil];

    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleWhiteLarge];
    spinner.center = CGPointMake(139.5, 75.5);

    [message addSubview:spinner];
    [spinner startAnimating];

    return message;
}

- (void)scrollViewDidEndDragging:(UIScrollView *)scroll willDecelerate:(BOOL)decelerate {

    // UITableView only moves in one direction, y axis
    if (!isUpdating) {

        NSInteger currentOffset = scroll.contentOffset.y;
        NSInteger maximumOffset = scroll.contentSize.height - scroll.frame.size.height;
        
        // Change 1.0 to adjust the distance from bottom
        if (maximumOffset - currentOffset <= 1.0) {
            isUpdating = true;
            [self update];
        }
    }
}

- (void) update {

    cell_count += 10;
    ISenseSearch *newSearch = [[ISenseSearch alloc] initWithQuery:currentQuery page:(currentPage + 1) itemsPerPage:10 andBuildType:APPEND];
    [self updateProjects:newSearch];
    isUpdating = false;
}

// There is a single column in this table
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}

// There are as many rows as there are projects
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
	
	if (![currentQuery isEqualToString:@""]) {

        if ([projectsFiltered count] == 0) {
            return 1;
        }

        return [projectsFiltered count];
    }

    return cell_count + 1;
}

-(void)updateProjects:(ISenseSearch *)iSS {
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{

        if (projects == nil) {

            projects = [[NSMutableArray alloc] init];
            projectsFiltered = [[NSMutableArray alloc] init];
            self.tableView.dataSource = self;
            self.tableView.delegate = self;
        }

        NSArray *fetchedProjectsArray = [isenseAPI getProjectsAtPage:iSS.page withPageLimit:iSS.perPage withFilter:CREATED_AT_DESC andQuery:iSS.query];

        // if the array returned back 0, the request likely timed out.
        // return here and the "No Projects Found" label will reappear.
        if (fetchedProjectsArray.count == 0) {
            [spinnerDialog dismissWithClickedButtonIndex:0 animated:YES];
            return;
        }

        if (![iSS.query isEqualToString:@""]){
            [projectsFiltered addObjectsFromArray:fetchedProjectsArray];
        } else {
            [projects addObjectsFromArray:fetchedProjectsArray];
        }

        currentPage = iSS.page;
        currentQuery = iSS.query;

        dispatch_async(dispatch_get_main_queue(), ^{

            [self.tableView reloadData];
            [spinnerDialog dismissWithClickedButtonIndex:0 animated:YES];

        });
    });
}


- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	
    if (indexPath.row == cell_count) { // Special Case 2
		
		UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"NoReuse"];
        cell.textLabel.text = @"Loading...";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc]
                                             initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleGray];
        
        // Spacer is a 1x1 transparent png
        UIImage *spacer = [UIImage imageNamed:@"spacer"];
        
        UIGraphicsBeginImageContext(spinner.frame.size);
        
        [spacer drawInRect:CGRectMake(0,0,spinner.frame.size.width,spinner.frame.size.height)];
        UIImage* resizedSpacer = UIGraphicsGetImageFromCurrentImageContext();
        
        UIGraphicsEndImageContext();
        cell.imageView.image = resizedSpacer;
        [cell.imageView addSubview:spinner];
        [spinner startAnimating];
        
        return cell;

	} else if (![currentQuery isEqualToString:@""] && [projectsFiltered count] == 0) {

        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"NoProjFoundCell"];
        cell.textLabel.text= @"No Projects Found";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        
        return cell;

    } else {

        int row = (int)indexPath.row;
        
        RProject *proj;
        if (![currentQuery isEqualToString:@""]) {
            proj = [projectsFiltered objectAtIndex:row];
        } else {
            proj = [projects objectAtIndex:row];
        }
        
        UITableViewCell *cell = [[ProjectCell alloc] initWithProject:proj];
        return cell;
    }
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {

    if (![currentQuery isEqualToString:@""]) {

        if ([projectsFiltered count] == 0) {
            return;
        }

        [self.delegate didFinishChoosingProject:self withID:[(RProject *)[projectsFiltered objectAtIndex:indexPath.row] project_id].intValue];
        [self.navigationController popViewControllerAnimated:YES];

        return;
    }

    if (indexPath.row == cell_count) {
        return;
    }

    // delegate the project selection back to the caller
    [self.delegate didFinishChoosingProject:self withID:[(RProject *)[projects objectAtIndex:indexPath.row] project_id].intValue];

    // if a navigation controller exists, pop the view controller from the navigation controller
    if (self.navigationController) {

        [self.navigationController popViewControllerAnimated:YES];
        return;
    }

    // otherwise, dismiss the view controller
    [self dismissViewControllerAnimated:YES completion:nil];
}

/* Search bar methods */
- (void)searchBarSearchButtonClicked:(UISearchBar *)search {

    spinnerDialog = [self getDispatchDialogWithMessage:@"Loading..."];
    [spinnerDialog show];
    [projectsFiltered removeAllObjects];
    [self handleSearch:search];
}

- (void)handleSearch:(UISearchBar *)search {

    NSString *query = [search.text copy];
    
    ISenseSearch *newSearch = [[ISenseSearch alloc] initWithQuery:query page:1 itemsPerPage:10 andBuildType:NEW];
    [self updateProjects:newSearch];

    [search resignFirstResponder];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *) search {

    [search setText:@""];
    [search resignFirstResponder];
    
    spinnerDialog = [self getDispatchDialogWithMessage:@"Loading..."];
    [spinnerDialog show];
    
    ISenseSearch *newSearch = [[ISenseSearch alloc] initWithQuery:@"" page:1 itemsPerPage:10 andBuildType:NEW];
    [self updateProjects:newSearch];
    [search setShowsCancelButton:false animated:true];
    [search sizeToFit];
}


@end
