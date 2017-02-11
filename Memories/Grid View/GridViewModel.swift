//
//  GridViewModel.swift
//  Memories
//
//  Created by Michael Brown on 16/07/2015.
//  Copyright © 2015 Michael Brown. All rights reserved.
//

import Foundation
import Photos
import PHAssetHelper
import ReactiveSwift
import Result


struct SectionChanges {
    let section: Int
    let nonIncremental: Bool
    let removed: [IndexPath]
    let inserted: [IndexPath]
    let changed: [IndexPath]
    let newItemCount: Int
    
    init(section: Int, removed: [IndexPath] = [], inserted: [IndexPath] = [], changed: [IndexPath] = [], newItemCount: Int = 0) {
        self.section = section
        self.nonIncremental = removed.count == 0 && inserted.count == 0 && changed.count == 0
        self.removed = removed
        self.inserted = inserted
        self.changed = changed
        self.newItemCount = newItemCount
    }
}

class GridViewModel: NSObject {
    private var disposeables = [Disposable?]()
    fileprivate let assetHelper = PHAssetHelper()
    private let dateFormatter = DateFormatter().with {
        $0.dateFormat = "MMMM dd"
    }
    fileprivate let assetFetchResults = MutableProperty([PHFetchResult<PHAsset>]())
    fileprivate let sectionChangesPipe = Signal<SectionChanges, NoError>.pipe()
    
    let photosAllowed = MutableProperty(false)
    let date = MutableProperty(Date())
    let resultsDate = MutableProperty(Date())
    let title = MutableProperty("Memories")
    var sectionChanged: Signal<SectionChanges, NoError> {
        get {
            return sectionChangesPipe.output
        }
    }
    
    var sectionCount : Int {
        get {
            return assetFetchResults.value.count
        }
    }
    
    override init() {
        super.init()
        createBindings()
    }
    
    deinit {
        if photosAllowed.value {
            PHPhotoLibrary.shared().unregisterChangeObserver(self)
        }
        disposeables.forEach {
            $0?.dispose()
        }
    }
    
    private func registerObservers() {
        PHPhotoLibrary.shared().register(self)

        disposeables = [
            NotificationCenter.default.reactive
                .notifications(forName: NSNotification.Name(PHAssetHelper.sourceTypesChangedNotification))
                .observeValues { [weak self] _ in
                    guard let me = self else { return }
                    // make a non-significant change to the date to force a reload of fetch results
                    me.date.value = me.date.value.addingTimeInterval(60)
            },
            NotificationCenter.default.reactive
                .notifications(forName: NSNotification.Name.UIApplicationDidBecomeActive)
                .combineLatest(with: photosAllowed.signal)
                .observeValues { [weak self] _ in
                    if let date = NotificationManager.launchDate() {
                        self?.date.value = date
                    }
            }
        ]
    }
    
    private func createBindings() {
        photosAllowed.signal.observeValues { _ in
            self.registerObservers()
        }
        
        date.signal.observeValues { date in
            self.assetFetchResults <~ self.updateFetchResults(for: date)
        }
        
        date.signal.observeValues { date in
            self.title.value = self.dateFormatter.string(from: date).uppercased() + " ▾" // ▼
        }
        
        assetFetchResults.signal.observeValues { _ in
            self.resultsDate.value = self.date.value
        }
    }
    
    private func updateFetchResults(for date: Date) -> SignalProducer<[PHFetchResult<PHAsset>], NoError> {
        return SignalProducer<[PHFetchResult<PHAsset>], NoError> { observer, _ in
            observer.send(value: self.assetHelper.fetchResultsForAllYears(with: date))
            observer.sendCompleted()
        }
        .start(on: QueueScheduler(qos: .userInitiated))
    }
    
    // MARK: - API
    func goToNextDay() {
        date.value = date.value.nextDay()
    }

    func goToPreviousDay() {
        date.value = date.value.previousDay()
    }
    
    func asset(at indexPath : IndexPath) -> PHAsset? {
        guard (indexPath as NSIndexPath).section < assetFetchResults.value.count &&
            (indexPath as NSIndexPath).item < assetFetchResults.value[(indexPath as NSIndexPath).section].count else {
            return nil
        }
        
        return assetFetchResults.value[(indexPath as NSIndexPath).section][(indexPath as NSIndexPath).item] as PHAsset?
    }
    
    func numberOfItems(in section : Int) -> Int {
        guard section < assetFetchResults.value.count else {
            return 0
        }
        
        return assetFetchResults.value[section].count
    }
    
    func year(for section : Int) -> Int {
        guard section < assetFetchResults.value.count else {
            return 0
        }
        
        let asset = assetFetchResults.value[section].firstObject!
        let creationDate = asset.creationDate!
        
        return creationDate.year
    }
    
    func fetchResult(for section : Int) -> PHFetchResult<PHAsset>? {
        guard section < assetFetchResults.value.count else {
            return nil
        }
        return assetFetchResults.value[section]
    }
    
    func photoViewModel(for indexPath: IndexPath) -> PhotosViewModel {
        var assets : [PHAsset] = [PHAsset]()
        var selectedIndex = 0
        var currentIndex = 0
        
        for (section, fetchResult) in assetFetchResults.value.enumerated() {
            fetchResult.enumerateObjects({ (asset, index, stop) -> Void in
                assets.append(asset)
                if (section == (indexPath as NSIndexPath).section && index == (indexPath as NSIndexPath).item) {
                    selectedIndex = currentIndex
                }
                currentIndex += 1
            })
        }            
        
        return PhotosViewModel(assets: assets, currentIndex: selectedIndex)
    }
    
    func indexPath(for selectedIndex: Int) -> IndexPath {
        var sectionTotal = 0
        
        for (section, fetchResult) in assetFetchResults.value.enumerated() {
            if sectionTotal + fetchResult.count > selectedIndex {
                return IndexPath(item: selectedIndex - sectionTotal, section: section)
            }
            sectionTotal += fetchResult.count
        }
        
        return IndexPath()
    }
}

extension GridViewModel : PHPhotoLibraryChangeObserver {
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        var cacheNeedsReset = false
        
        for section in (0 ..< sectionCount).reversed() {
            if let fetchResult = fetchResult(for: section),
                let changes = changeInstance.changeDetails(for: fetchResult) {
                let newFetchResult = changes.fetchResultAfterChanges
                
                if newFetchResult.count == 0 {
                    assetFetchResults.value.remove(at: section)
                } else {
                    assetFetchResults.value[section] = newFetchResult
                }
                
                let sectionChanges: SectionChanges
                if !changes.hasIncrementalChanges || changes.hasMoves {
                    sectionChanges = SectionChanges(section: section, newItemCount: newFetchResult.count)
                } else {
                    sectionChanges = SectionChanges(section: section,
                                                    removed: changes.removedIndexes?.indexPathsFromIndexes(in: section) ?? [],
                                                    inserted: changes.insertedIndexes?.indexPathsFromIndexes(in: section) ?? [],
                                                    changed: changes.changedIndexes?.indexPathsFromIndexes(in: section) ?? [],
                                                    newItemCount: newFetchResult.count)
                }
                
                sectionChangesPipe.input.send(value: sectionChanges)
                cacheNeedsReset = true
            }
        }
        
        if (cacheNeedsReset) {
            assetHelper.refreshDatesMapCache()
        }
    }
}
