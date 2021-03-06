//
//  SettingsViewController.swift
//  Memories
//
//  Created by Michael Brown on 10/09/2015.
//  Copyright © 2015 Michael Brown. All rights reserved.
//

import UIKit
import MessageUI
import ReactiveCocoa
import ReactiveSwift

class SettingsViewController: UITableViewController, MFMailComposeViewControllerDelegate {

    @IBOutlet weak var notificationsSwitch: UISwitch!
    @IBOutlet weak var timePicker: UIDatePicker!
    @IBOutlet weak var feedbackCell: UITableViewCell!
    @IBOutlet weak var rateCell: UITableViewCell!
    @IBOutlet weak var upgradeCell: UITableViewCell!
    @IBOutlet weak var upgradeLabel: UILabel!
    @IBOutlet weak var upgradeButton: UIButton!
    @IBOutlet weak var restoreButton: UIButton!
    @IBOutlet weak var thankYouLabel: UILabel!
    @IBOutlet weak var sourceIncludeCurrentYearSwitch: UISwitch!
    @IBOutlet weak var sourcePhotoLibrarySwitch: UISwitch!
    @IBOutlet weak var sourceICloudSharedSwitch: UISwitch!
    @IBOutlet weak var sourceITunesSwitch: UISwitch!

    let viewModel: SettingsViewModel
    
    required init?(coder aDecoder: NSCoder) {
        viewModel = SettingsViewModel()

        super.init(coder: aDecoder)
    }
    
    private func initUI() {
        notificationsSwitch.isOn = viewModel.notificationsEnabled.value
        timePicker.date = timePicker.calendar.date(from: DateComponents(era: 1, year: 1970, month: 1, day: 1,
                                                                        hour: viewModel.notificationTime.value.hour,
                                                                        minute: viewModel.notificationTime.value.minute,
                                                                        second: 0, nanosecond: 0))!
        
        sourceIncludeCurrentYearSwitch.isOn = viewModel.sourceIncludeCurrentYear.value
        sourcePhotoLibrarySwitch.isOn = viewModel.sourcePhotoLibrary.value
        sourceICloudSharedSwitch.isOn = viewModel.sourceICloudShare.value
        sourceITunesSwitch.isOn = viewModel.sourceITunes.value
        upgradeButton.isEnabled = false
        restoreButton.isEnabled = false
    }
    
    private func bindToModel() {
        viewModel.notificationsEnabled.producer.startWithValues { [unowned self] in
            if $0 {
                NotificationManager.enableNotifications()
                self.timePicker.isUserInteractionEnabled = true
                self.timePicker.alpha = 1
            } else {
                NotificationManager.disableNotifications()
                self.timePicker.isUserInteractionEnabled = false
                self.timePicker.alpha = 0.5
            }
        }
        
        viewModel.userHasUpgraded.producer.startWithValues {
            [unowned self] upgraded in
            UIView.animate(withDuration: 0.25) {
                self.upgradeButton.alpha = upgraded ? 0 : 1
                self.restoreButton.alpha = upgraded ? 0 : 1
                self.thankYouLabel.alpha = upgraded ? 1 : 0
                if upgraded { self.upgradeLabel.text = "" }
                self.tableView.beginUpdates()
                self.tableView.endUpdates()
            }
        }

        viewModel.upgradeButtonText.startWithSignal { signal, _ in
            signal.observeValues {
                [unowned self] in
                self.upgradeButton.setTitle($0, for: .normal)
            }
            signal.skip(first: 1).observeValues {
                [unowned self] _ in
                self.upgradeButton.isEnabled = true
                self.restoreButton.isEnabled = true
            }
        }
    }
    
    private func bindControls() {
        viewModel.notificationsEnabled <~ notificationsSwitch.reactive.isOnValues
        viewModel.notificationTime <~ timePicker.reactive.dates.map {
            (hour: self.timePicker.calendar.component(.hour, from: $0),
             minute: self.timePicker.calendar.component(.minute, from: $0))
        }
        
        viewModel.sourceIncludeCurrentYear <~ sourceIncludeCurrentYearSwitch.reactive.isOnValues
        viewModel.sourcePhotoLibrary <~ sourcePhotoLibrarySwitch.reactive.isOnValues
        viewModel.sourceICloudShare <~ sourceICloudSharedSwitch.reactive.isOnValues
        viewModel.sourceITunes <~ sourceITunesSwitch.reactive.isOnValues
        
        upgradeButton.reactive.controlEvents(.touchUpInside).observeValues { _ in
            self.viewModel.userHasUpgraded <~ self.viewModel.upgrade()
        }
        
        restoreButton.reactive.controlEvents(.touchUpInside).observeValues { _ in
            self.viewModel.userHasUpgraded <~ self.viewModel.restore()
        }
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        initUI()
        bindToModel()
        bindControls()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // this is called when the settings view is dismissed via the Done button
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        viewModel.commit()
    }
    
    // MARK: UITableViewDelegate
    
    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        let cell = tableView.cellForRow(at: indexPath)
        
        if cell == rateCell {
            rateApp()
        }
        else if cell == feedbackCell {
            sendFeedback()
        }
    }
    
    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        let timePickerIndexPath = IndexPath(row: 1, section: 1)
        let upgradeIndexPath = IndexPath(row: 0, section: 0)
        
        let height : CGFloat
        switch indexPath {
        case timePickerIndexPath:
            height = 162
        case upgradeIndexPath:
            let attributedString = NSAttributedString(string: upgradeLabel.text!, attributes: [NSAttributedStringKey.font : UIFont.systemFont(ofSize: 14)])
            let rect = attributedString.boundingRect(with: CGSize(width: tableView.bounds.width - 32, height: CGFloat.greatestFiniteMagnitude)
                , options: [.usesLineFragmentOrigin, .usesFontLeading]
                , context: nil)
            
            height = rect.height + 44 // space for the buttons etc
        default:
            height = 44
        }
        
        return height
    }

    private func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            let composer = MFMailComposeViewController()
            composer.mailComposeDelegate = self;
            
            let device = UIDevice.current
            let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"]
            let appBuild = Bundle.main.infoDictionary?["CFBundleVersion"]
            
            let body = "<div><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><hr><center>Developer Support Information</center><ul><li>Device Version: \(device.systemVersion)</li><li>Device Type: \(device.modelName)</li><li>App Version: \(appVersion!), Build: \(appBuild!)</li></ul><hr></div>"
            composer.setToRecipients(["memories@michael-brown.net"]);
            composer.setSubject("Memories Feedback")
            composer.setMessageBody(body, isHTML: true);
            
            self.present(composer, animated: true, completion: nil)
        } else {
            let title = NSLocalizedString("No e-mail account configured", comment: "No e-mail account configured") + "\nContact: memories@michael-brown.net"

            let alert = UIAlertController(title: title, message: "", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
            self.present(alert, animated: true, completion: nil)
        }
    }
    
    private func rateApp() {
        let appId = 1037130497
        let appStoreURL = URL(string: "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=\(appId)&pageNumber=0&sortOrdering=2&mt=8")!
        
        if UIApplication.shared.canOpenURL(appStoreURL) {
            UIApplication.shared.openURL(appStoreURL)
        }
    }
    
    // MARK: MFMailComposeViewControllerDelegate

    func mailComposeController(_ controller: MFMailComposeViewController, didFinishWith result: MFMailComposeResult, error: Error?) {
        self.dismiss(animated: true, completion: nil)
    }
    
}
