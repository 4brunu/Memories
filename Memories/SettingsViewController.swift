//
//  SettingsViewController.swift
//  Memories
//
//  Created by Michael Brown on 10/09/2015.
//  Copyright © 2015 Michael Brown. All rights reserved.
//

import UIKit
import MessageUI

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

    var viewModel : SettingsViewModel? {
        willSet {
            if let model = viewModel where newValue == nil {
                model.notificationsEnabled.bind(nil)
                model.notificationHour.bind(nil)
                model.notificationMinute.bind(nil)
                model.userHasUpgraded.bind(nil)
                model.upgradeButtonText.bind(nil)
                model.storeAvailable.bind(nil)
            }
        }
        
        didSet {
            if let model = viewModel {
                model.notificationsEnabled.bindAndFire {
                    [unowned self] in
                    self.notificationsSwitch.on = $0
                    if $0 {
                        NotificationManager.enableNotifications()
                        self.timePicker.userInteractionEnabled = true
                        self.timePicker.alpha = 1
                    } else {
                        NotificationManager.disableNotifications()
                        self.timePicker.userInteractionEnabled = false
                        self.timePicker.alpha = 0.5
                    }
                }
                
                model.notificationHour.bindAndFire {
                    [unowned self] in
                    let hour = $0
                    let minute = model.notificationMinute.value
                    self.timePicker.date = self.timePicker.calendar.dateWithEra(1, year: 1970, month: 1, day: 1, hour: hour, minute: minute, second: 0, nanosecond: 0)!
                }
                
                model.notificationMinute.bindAndFire {
                    [unowned self] in
                    let hour = model.notificationHour.value
                    let minute = $0
                    self.timePicker.date = self.timePicker.calendar.dateWithEra(1, year: 1970, month: 1, day: 1, hour: hour, minute: minute, second: 0, nanosecond: 0)!
                }
                
                model.userHasUpgraded.bindAndFire {
                    [unowned self] in
                    let value = $0
                    UIView.animateWithDuration(0.25) {
                        self.upgradeButton.alpha = value ? 0 : 1
                        self.restoreButton.alpha = value ? 0 : 1
                        self.thankYouLabel.alpha = value ? 1 : 0
                        if value { self.upgradeLabel.text = "" }
                        self.tableView.beginUpdates()
                        self.tableView.endUpdates()
                    }
                }
                
                model.upgradeButtonText.bindAndFire {
                    [unowned self] in
                    self.upgradeButton.setTitle($0, forState: .Normal)
                }
                
                model.storeAvailable.bindAndFire {
                    [unowned self] in
                    let value = $0
                    self.upgradeButton.enabled = value
                    self.restoreButton.enabled = value
                }
            }
        }
    }
    
    override func viewWillAppear(animated: Bool) {
        let notificationTime = NotificationManager.notificationTime()
        let notificationsEnabled = NotificationManager.notificationsEnabled() && NotificationManager.notificationsAllowed()
        viewModel = SettingsViewModel(notificationsEnabled: notificationsEnabled, notificationHour: notificationTime.hour, notificationMinute: notificationTime.minute)
    }
    
    override func viewWillDisappear(animated: Bool) {
        viewModel = nil
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    // this is called when the settings view is dismissed via the Done button
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // schedule or disable notifications
        if viewModel!.notificationsEnabled.value {
            NotificationManager.setNotificationTime(viewModel!.notificationHour.value, viewModel!.notificationMinute.value)
            NotificationManager.scheduleNotifications()
        } else {
            NotificationManager.disableNotifications()
        }
    }
    
    // MARK: UITableViewDelegate
    
    override func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        let cell = tableView.cellForRowAtIndexPath(indexPath)
        
        if cell == rateCell {
            rateApp()
        }
        else if cell == feedbackCell {
            sendFeedback()
        }
    }
    
    override func tableView(tableView: UITableView, heightForRowAtIndexPath indexPath: NSIndexPath) -> CGFloat {
        let timePickerIndexPath = NSIndexPath(forRow: 1, inSection: 1)
        let upgradeIndexPath = NSIndexPath(forRow: 0, inSection: 0)
        
        let height : CGFloat
        switch indexPath {
        case timePickerIndexPath:
            height = 162
            break
        case upgradeIndexPath:
            let attributedString = NSAttributedString(string: upgradeLabel.text!, attributes: [NSFontAttributeName : UIFont.systemFontOfSize(14)])
            let rect = attributedString.boundingRectWithSize(CGSizeMake(upgradeCell.frame.width - 32, CGFloat.max)
                , options: [.UsesLineFragmentOrigin, .UsesFontLeading]
                , context: nil)
            
            height = rect.height + 44 // space for the buttons etc
            break
        default:
            height = 44
        }
        
        return height
    }
    
    // MARK: Actions
    
    @IBAction func notificationSwitchValueChanged(sender: UISwitch) {
        viewModel?.notificationsEnabled.value = sender.on
    }
    
    @IBAction func timePickerValueChanged(sender: UIDatePicker) {
        let hour = sender.calendar.component(.Hour, fromDate: timePicker.date)
        let minute = sender.calendar.component(.Minute, fromDate: timePicker.date)

        // read both values from the control first, then set the model values
        viewModel?.notificationHour.value = hour
        viewModel?.notificationMinute.value = minute
    }

    @IBAction func upgradeTapped(sender: UIButton) {
        UpgradeManager.upgrade {
            self.viewModel?.userHasUpgraded.value = $0
        }
    }
    
    @IBAction func restoreTapped(sender: UIButton) {
        UpgradeManager.restore {
            self.viewModel?.userHasUpgraded.value = $0
        }
    }
    
    func sendFeedback() {
        if MFMailComposeViewController.canSendMail() {
            let composer = MFMailComposeViewController()
            composer.mailComposeDelegate = self;
            
            let device = UIDevice.currentDevice()
            let appVersion = NSBundle.mainBundle().infoDictionary?["CFBundleShortVersionString"]
            let appBuild = NSBundle.mainBundle().infoDictionary?["CFBundleVersion"]
            
            let body = "<div><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><br><hr><center>Developer Support Information</center><ul><li>Device Version: \(device.systemVersion)</li><li>Device Type: \(device.modelName)</li><li>App Version: \(appVersion!), Build: \(appBuild!)</li></ul><hr></div>"
            composer.setToRecipients(["memories@michael-brown.net"]);
            composer.setSubject("Memories Feedback")
            composer.setMessageBody(body, isHTML: true);
            
            self.presentViewController(composer, animated: true, completion: nil)
        } else {
            let title = NSLocalizedString("No e-mail account configured", comment: "No e-mail account configured") + "\nContact: memories@michael-brown.net"

            let alert = UIAlertController(title: title, message: "", preferredStyle: .Alert)
            alert.addAction(UIAlertAction(title: "OK", style: .Default, handler: nil))
            self.presentViewController(alert, animated: true, completion: nil)
        }
    }
    
    func rateApp() {
        let appId = 1037130497
        let appStoreURL = NSURL(string: "itms-apps://itunes.apple.com/WebObjects/MZStore.woa/wa/viewContentsUserReviews?type=Purple+Software&id=\(appId)&pageNumber=0&sortOrdering=2&mt=8")!
        
        if UIApplication.sharedApplication().canOpenURL(appStoreURL) {
            UIApplication.sharedApplication().openURL(appStoreURL)
        }
    }
    
    // MARK: MFMailComposeViewControllerDelegate

    func mailComposeController(controller: MFMailComposeViewController, didFinishWithResult result: MFMailComposeResult, error: NSError?) {
        self.dismissViewControllerAnimated(true, completion: nil)
    }
    
}
