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

#import "PhotoProcessPass.h"

typedef enum
{
    BlurToolTypeNone,
    BlurToolTypeRadial,
    BlurToolTypeLinear
} BlurToolType;

@interface PhotoBlurPass : PhotoProcessPass

@property (nonatomic, assign) BlurToolType type;
@property (nonatomic, assign) CGFloat size;
@property (nonatomic, assign) CGFloat falloff;
@property (nonatomic, assign) CGPoint point;
@property (nonatomic, assign) CGFloat angle;

@end
