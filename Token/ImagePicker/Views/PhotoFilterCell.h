// Copyright (c) 2017 Token Browser, Inc
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.
//
// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

#import <UIKit/UIKit.h>

@class PhotoFilter;

@interface PhotoFilterCell : UICollectionViewCell

@property (nonatomic, readonly) NSString *filterIdentifier;

- (void)setPhotoFilter:(PhotoFilter *)photoFilter;
- (void)setFilterSelected:(BOOL)selected;

- (void)setImage:(UIImage *)image;
- (void)setImage:(UIImage *)image animated:(bool)animated;

+ (CGFloat)filterCellWidth;

@end

extern NSString * const PhotoFilterCellKind;
