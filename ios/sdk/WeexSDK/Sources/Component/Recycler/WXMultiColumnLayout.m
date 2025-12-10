/*
 * Licensed to the Apache Software Foundation (ASF) under one
 * or more contributor license agreements.  See the NOTICE file
 * distributed with this work for additional information
 * regarding copyright ownership.  The ASF licenses this file
 * to you under the Apache License, Version 2.0 (the
 * "License"); you may not use this file except in compliance
 * with the License.  You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing,
 * software distributed under the License is distributed on an
 * "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
 * KIND, either express or implied.  See the License for the
 * specific language governing permissions and limitations
 * under the License.
 */

#import "WXMultiColumnLayout.h"
#import "NSArray+Weex.h"
#import "WXUtility.h"
#import "WXAssert.h"

NSString * const kCollectionSupplementaryViewKindHeader = @"WXCollectionSupplementaryViewKindHeader";
NSString * const kMultiColumnLayoutHeader = @"WXMultiColumnLayoutHeader";
NSString * const kMultiColumnLayoutCell = @"WXMultiColumnLayoutCell";

@interface WXMultiColumnLayoutHeaderAttributes : UICollectionViewLayoutAttributes

@property (nonatomic, assign) BOOL isSticky;
@property (nonatomic, assign) CGFloat topOffset;

@end

@implementation WXMultiColumnLayoutHeaderAttributes

- (id)copyWithZone:(NSZone *)zone
{
    WXMultiColumnLayoutHeaderAttributes *copy = [super copyWithZone:zone];
    copy.isSticky = self.isSticky;
    
    return copy;
}

@end

@interface WXMultiColumnLayout ()

@property (nonatomic, strong) NSMutableDictionary<NSString *, NSDictionary<id, UICollectionViewLayoutAttributes *> *> *layoutAttributes;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *columnsMaxPositions;
@property (nonatomic, assign) CGFloat maxCellHeight;

@end

@implementation WXMultiColumnLayout

- (instancetype)init
{
    if (self = [super init]) {
        _layoutAttributes = [NSMutableDictionary dictionary];
        _columnsMaxPositions = [NSMutableArray array];
        _scrollDirection = UICollectionViewScrollDirectionVertical;
    }
    
    return self;
}

//Under system version 10.0, UICollectionViewLayout.collectionView seems be unsafe_unretain rather than weak. sometime when the collectionView is released, and the layout is not released, it may crash.
- (UICollectionView *)weakCollectionView
{
    if ([[[UIDevice currentDevice] systemVersion] floatValue]<10.0f) {
        return self.weak_collectionView;
    } else {
        return self.collectionView;
    }
}

#pragma mark - Public Accessors

- (void)setColumnCount:(WXLength *)columnCount
{
    if (!(columnCount.isAuto && _columnCount.isAuto) || _columnCount.intValue != columnCount.intValue) {
        _columnCount = columnCount;
        [self _cleanComputed];
    }
}

- (void)setColumnWidth:(WXLength *)columnWidth
{
    if (!(columnWidth.isAuto && _columnWidth.isAuto) || _columnWidth.floatValue != columnWidth.floatValue) {
        _columnWidth = columnWidth;
        [self _cleanComputed];
    }
}

- (void)setColumnGap:(float)columnGap
{
    if (_columnGap != columnGap) {
        _columnGap = columnGap;
        [self _cleanComputed];
    }
}

- (void)setLeftGap:(float)leftGap
{
    if (_leftGap != leftGap) {
        _leftGap = leftGap;
        [self _cleanComputed];
    }
}

- (void)setRightGap:(float)rightGap
{
    if (_rightGap != rightGap) {
        _rightGap = rightGap;
        [self _cleanComputed];
    }
}

- (CGFloat)computedColumnWidth
{
    WXAssert([_columnWidth isFixed], @"column width must be calculated by core.");
    return _columnWidth.floatValue;
}

- (int)computedColumnCount
{
    WXAssert([_columnCount isFixed], @"column count must be calculated by core.");
    return _columnCount.intValue;
}

- (CGFloat)computedHeaderWidth
{
    UIEdgeInsets insets = [self.delegate collectionView:[self weakCollectionView] insetForLayout:self];
    return self.contentWidth - (insets.left + insets.right);
}

#pragma mark - Methods to Override for UICollectionViewLayout

- (void)prepareLayout
{
    [super prepareLayout];
    
    [self _cleanup];
    
    NSInteger numberOfSections = [[self weakCollectionView]  numberOfSections];
    UIEdgeInsets insets = [self.delegate collectionView:[self weakCollectionView]  insetForLayout:self];
    
    float columnWidth = self.computedColumnWidth;
    int columnCount = self.computedColumnCount;
    float columnGap = self.columnGap;
    CGFloat currentMaxPosition = insets.top;
    if (_scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        currentMaxPosition = insets.left;
        _maxCellHeight = 0;
    }
    NSMutableDictionary *headersAttributes = [NSMutableDictionary dictionaryWithCapacity:numberOfSections];
    NSMutableDictionary *cellAttributes = [NSMutableDictionary dictionary];
    for (NSInteger i = 0; i < columnCount; i++) {
        [self.columnsMaxPositions addObject:@(currentMaxPosition)];
    }
    
    for (NSInteger section = 0; section < numberOfSections; section++) {
        BOOL hasHeader = [self.delegate collectionView:[self weakCollectionView]  layout:self hasHeaderInSection:section];
        // header
        if (hasHeader) {
            CGFloat headerHeight = [self.delegate collectionView:[self weakCollectionView]  layout:self heightForHeaderInSection:section];
            WXMultiColumnLayoutHeaderAttributes *headerAttributes = [WXMultiColumnLayoutHeaderAttributes layoutAttributesForSupplementaryViewOfKind:kCollectionSupplementaryViewKindHeader withIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
            headerAttributes.frame = CGRectMake(insets.left, currentMaxPosition, self.contentWidth - (insets.left + insets.right), headerHeight);
            headerAttributes.isSticky = [self.delegate collectionView:[self weakCollectionView] layout:self isNeedStickyForHeaderInSection:section];
            headerAttributes.topOffset = [self.delegate collectionView:[self weakCollectionView] layout:self topOffsetForHeaderInSection:section];
            headerAttributes.zIndex = headerAttributes.isSticky ? 1 : 0;
            headersAttributes[@(section)] = headerAttributes;
            currentMaxPosition = CGRectGetMaxY(headerAttributes.frame);
            [self _columnsReachToPosition:currentMaxPosition];
        }
        
        // cells
        
        @try {
            for (NSInteger item = 0; item < [[self weakCollectionView] numberOfItemsInSection:section]; item++) {
                NSIndexPath *indexPath = [NSIndexPath indexPathForItem:item inSection:section];
                CGSize itemSize = [self.delegate collectionView:[self weakCollectionView] layout:self sizeForItemAtIndexPath:indexPath];
                CGFloat itemHeight = itemSize.height;
                UICollectionViewLayoutAttributes *itemAttributes = [UICollectionViewLayoutAttributes layoutAttributesForCellWithIndexPath:indexPath];
                NSUInteger column = [self _minPositionColumnForAllColumns];
                if (column >= [self.columnsMaxPositions count]) {
                    return;
                }
                
                CGFloat x, y, width, height;
                if (_scrollDirection == UICollectionViewScrollDirectionHorizontal) {
                    // Horizontal layout: items flow left to right, columns are rows
                    x = [self.columnsMaxPositions[column] floatValue];
                    y = 0;
                    width = columnWidth;  // In horizontal mode, itemHeight becomes width
                    height = itemHeight; // columnWidth becomes height
                    self.columnsMaxPositions[column] = @(x + width);
                    if (itemHeight > _maxCellHeight) {
                        _maxCellHeight = itemHeight;
                    }
                } else {
                    // Vertical layout: items flow top to bottom, columns are columns
                    x = insets.left + (columnWidth + columnGap) * column + _leftGap;
                    y = [self.columnsMaxPositions[column] floatValue];
                    width = columnWidth;
                    height = itemHeight;
                    self.columnsMaxPositions[column] = @(y + height);
                }
                
                itemAttributes.frame = CGRectMake(x, y, width, height);
                cellAttributes[indexPath] = itemAttributes;
            }
        } @catch (NSException *exception) {
            WXLog(@"%@", exception);
        }
        currentMaxPosition = [self _maxPositionForAllColumns];
        [self _columnsReachToPosition:currentMaxPosition];
    }
    
    if (_scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        currentMaxPosition = currentMaxPosition + insets.right;
    } else {
        currentMaxPosition = currentMaxPosition + insets.bottom;
    }
    [self _columnsReachToPosition:currentMaxPosition];
    
    self.layoutAttributes[kMultiColumnLayoutHeader] = headersAttributes;
    self.layoutAttributes[kMultiColumnLayoutCell] = cellAttributes;
}

- (CGSize)collectionViewContentSize
{
    NSInteger numberOfSections = [[self weakCollectionView] numberOfSections];
    if (numberOfSections == 0) {
        return CGSizeZero;
    }
    CGSize contentSize;
    if (_scrollDirection == UICollectionViewScrollDirectionHorizontal) {
        contentSize = CGSizeMake(MAX([self _maxPositionForAllColumns], self.minContentSizeHeight), _maxCellHeight);
    } else {
        contentSize = CGSizeMake(self.contentWidth, MAX([self _maxPositionForAllColumns], self.minContentSizeHeight));
    }
    
    return contentSize;
}

- (NSArray<UICollectionViewLayoutAttributes *> *)layoutAttributesForElementsInRect:(CGRect)rect
{
    NSMutableArray<WXMultiColumnLayoutHeaderAttributes *> *stickyHeaders = [NSMutableArray array];
    NSMutableArray<UICollectionViewLayoutAttributes *> *result = [NSMutableArray array];
    
    [self.layoutAttributes enumerateKeysAndObjectsUsingBlock:^(NSString * _Nonnull kind, NSDictionary<id,UICollectionViewLayoutAttributes *> * _Nonnull dictionary, BOOL * _Nonnull stop) {
        [dictionary enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, UICollectionViewLayoutAttributes * _Nonnull attributes, BOOL * _Nonnull stop) {
            if (attributes.representedElementKind == kCollectionSupplementaryViewKindHeader
                && [self.delegate collectionView:[self weakCollectionView] layout:self isNeedStickyForHeaderInSection:attributes.indexPath.section]) {
                [stickyHeaders addObject:(WXMultiColumnLayoutHeaderAttributes *)attributes];
            } else if (CGRectIntersectsRect(rect, attributes.frame)) {
                [result addObject:attributes];
            }
        }];
    }];
    
    [stickyHeaders sortUsingComparator:^NSComparisonResult(WXMultiColumnLayoutHeaderAttributes *obj1, WXMultiColumnLayoutHeaderAttributes *obj2) {
        if (obj1.indexPath.section < obj2.indexPath.section) {
            return NSOrderedAscending;
        } else {
            return NSOrderedDescending;
        }
    }];
    
    for (int i = 0; i < stickyHeaders.count; i++) {
        WXMultiColumnLayoutHeaderAttributes *header = stickyHeaders[i];
        [self _adjustStickyForHeaderAttributes:header next:(i == stickyHeaders.count - 1) ? nil : stickyHeaders[i + 1]];
        [result addObject:header];
    }
    
    WXLogDebug(@"return result attributes:%@ for rect:%@", result, NSStringFromCGRect(rect));
    
    return result;
}

- (void)_adjustStickyForHeaderAttributes:(WXMultiColumnLayoutHeaderAttributes *)header
                                   next:(WXMultiColumnLayoutHeaderAttributes *)nextHeader
{
    CGRect bounds = [self weakCollectionView].bounds;
    CGFloat originY = header.frame.origin.y;
    CGFloat maxY = nextHeader ? (nextHeader.frame.origin.y - header.frame.size.height) : (CGRectGetMaxY(bounds) - header.frame.size.height);
    CGFloat currentY = CGRectGetMaxY(bounds) - bounds.size.height + [self weakCollectionView].contentInset.top + header.topOffset;
    CGFloat resultY = originY > maxY ? originY : MIN(MAX(currentY, originY), maxY);
    CGPoint origin = header.frame.origin;
    origin.y = resultY;
    
    header.frame = (CGRect){origin, header.frame.size};
    header.hidden = NO;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForSupplementaryViewOfKind:(NSString *)elementKind atIndexPath:(NSIndexPath *)indexPath
{
    if ([elementKind isEqualToString:kCollectionSupplementaryViewKindHeader]) {
        UICollectionViewLayoutAttributes *attributes = self.layoutAttributes[kMultiColumnLayoutHeader][@(indexPath.section)];
        if (!attributes) {
            attributes = [UICollectionViewLayoutAttributes layoutAttributesForSupplementaryViewOfKind:elementKind withIndexPath:indexPath];
            attributes.frame = CGRectZero;
            attributes.hidden = YES;
        }
        WXLogDebug(@"return header attributes:%@ for index path:%@", attributes, indexPath);
        
        return attributes;
    }
    
    return nil;
}

- (UICollectionViewLayoutAttributes *)layoutAttributesForItemAtIndexPath:(NSIndexPath *)indexPath
{
    if (self.layoutAttributes.count == 0) {
        [self prepareLayout];
    }
    
    UICollectionViewLayoutAttributes *attributes = self.layoutAttributes[kMultiColumnLayoutCell][indexPath];
    WXLogDebug(@"return item attributes:%@ for index path:%@", attributes, indexPath);
    return attributes;
}

- (BOOL)shouldInvalidateLayoutForBoundsChange:(CGRect)newBounds
{
    __block BOOL hasStickyHeader = NO;
    [self.layoutAttributes[kMultiColumnLayoutHeader] enumerateKeysAndObjectsUsingBlock:^(id  _Nonnull key, UICollectionViewLayoutAttributes * _Nonnull obj, BOOL * _Nonnull stop) {
        WXMultiColumnLayoutHeaderAttributes *attribute = (WXMultiColumnLayoutHeaderAttributes *)obj;
        if (attribute.isSticky) {
            hasStickyHeader = YES;
            *stop = YES;
        }
    }];
    
    if (hasStickyHeader) {
        // always return yes no trigger resetting sticky header's frame.
        return YES;
    } else {
        CGRect oldBounds = [self weakCollectionView].bounds;
        if (CGRectGetWidth(newBounds) != CGRectGetWidth(oldBounds)) {
            return YES;
        }
    }
    
    return NO;
}

#pragma mark - Private

- (CGFloat)contentWidth
{
    return [self.delegate collectionView:[self weakCollectionView] contentWidthForLayout:self];
}



- (CGFloat)_maxPositionForAllColumns
{
    CGFloat maxValue = 0.0;
    for (NSNumber *number in self.columnsMaxPositions) {
        CGFloat value = [number floatValue];
        if (value > maxValue) {
            maxValue = value;
        }
    }
    
    return maxValue;
}

- (NSUInteger)_minPositionColumnForAllColumns
{
    __block NSUInteger index = 0;
    __block CGFloat minValue = FLT_MAX;
    
    [self.columnsMaxPositions enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        CGFloat value = [obj floatValue];
        if (value < minValue) {
            minValue = value;
            index = idx;
        }
    }];
    
    return index;
}

- (void)_columnsReachToPosition:(CGFloat)position
{
    for (NSInteger i = 0; i < self.columnsMaxPositions.count; i ++) {
        self.columnsMaxPositions[i] = @(position);
    }
}

- (void)_cleanup
{
    [self.layoutAttributes removeAllObjects];
    [self.columnsMaxPositions removeAllObjects];
}

- (void)_cleanComputed
{
}

- (void)invalidateLayout
{
    [super invalidateLayout];
    
    [self _cleanComputed];
}

@end
