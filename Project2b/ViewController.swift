//
//  ViewController.swift
//  Project2b
//
//  Created by Charles Martin Reed on 9/3/18.
//  Copyright © 2018 Charles Martin Reed. All rights reserved.
//

import UIKit
import SpriteKit
import ARKit
import CoreLocation
import GameplayKit

class ViewController: UIViewController, ARSKViewDelegate, CLLocationManagerDelegate {
    
    //MARK:- Properties
    let locationManager = CLLocationManager()
    var userLocation = CLLocation()
    var sightsJSON: JSON! //this will store the wikipedia data we get from our URL request
    
    //because initial heading is often inaccurate, we need to keep count of the user heading and disregard the initial one
    var userHeading = 0.0
    var headingCount = 0
    
    var pages = [UUID: String]()
    
    
    @IBOutlet var sceneView: ARSKView!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        // Set the view's delegate
        sceneView.delegate = self
        
        // Show statistics such as fps and node count
        sceneView.showsFPS = true
        sceneView.showsNodeCount = true
        
        // Load the SKScene from 'Scene.sks'
        if let scene = SKScene(fileNamed: "Scene") {
            sceneView.presentScene(scene)
        }
        
        //setting up the location manager
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest //within a matter of meters, when outside
        locationManager.requestWhenInUseAuthorization() //remains authorized in the future, once granted.
    }
    
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        let configuration = AROrientationTrackingConfiguration()

        // Run the view's session
        sceneView.session.run(configuration)
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        // Pause the view's session
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Release any cached data, images, etc that aren't in use.
    }
    
    // MARK: - ARSKViewDelegate
    
    func view(_ view: ARSKView, nodeFor anchor: ARAnchor) -> SKNode? {
        
        //create a label node showing the title for this anchor
        let labelNode = SKLabelNode(text: pages[anchor.identifier])
        labelNode.horizontalAlignmentMode = .center
        labelNode.verticalAlignmentMode = .center
        
        //scale up the label's size so we have some margin - making it slightly larger
        let size = labelNode.frame.size.applying(CGAffineTransform(scaleX: 1.1, y: 1.4))
        
        //create a background node using this new size, rounding its corners
        let backgroundNode = SKShapeNode(rectOf: size, cornerRadius: 10)
        
        //fill it in with a random color
        backgroundNode.fillColor = UIColor(hue: CGFloat(GKRandomSource.sharedRandom().nextUniform()), saturation: 0.5, brightness: 0.4, alpha: 0.9)
        
        //draw a border around it using a more opaque version of its fill color
        backgroundNode.strokeColor = backgroundNode.fillColor.withAlphaComponent(1)
        backgroundNode.lineWidth = 2
        
        //add the label to the background then send back to the background
        backgroundNode.addChild(labelNode)
        
        return backgroundNode;
    }
    
    func session(_ session: ARSession, didFailWithError error: Error) {
        // Present an error message to the user
        
    }
    
    func sessionWasInterrupted(_ session: ARSession) {
        // Inform the user that the session has been interrupted, for example, by presenting an overlay
        
    }
    
    func sessionInterruptionEnded(_ session: ARSession) {
        // Reset tracking and/or remove existing anchors if consistent tracking is required
        
    }
    
    //MARK:- CLLocationManager delegate methods
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        
        //if we were authorized, get the user's location
        if status == .authorizedWhenInUse {
            locationManager.requestLocation()
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        //contains a list of locations for the user
        //deferred updates lets iOS buffer the user locations and then send them to an app for more efficient polling
        //we're pulling out the last location because we want to make sure that we are using the most recent, accurate one
        guard let location = locations.last else { return }
        userLocation = location
        
        //call the fetch on a background thread
        DispatchQueue.global().async {
            
            self.fetchSights()
        }
        
    }
    
    func fetchSights() {
        //called when we receive our location information from user
        //create a URL that requests wikipedia data
        //fetch
        //use SwiftyJSON to parse the data
        //read the user's heading, i.e,. the direction they're pointing their phone is
        
        let urlString = "https://en.wikipedia.org/w/api.php?ggscoord=\(userLocation.coordinate.latitude)%7C\(userLocation.coordinate.longitude)&action=query&prop=coordinates%7Cpageimages%7Cpageterms&colimit=50&piprop=thumbnail&pithumbsize=500&pilimit=50&wbptterms=description&generator=geosearch&ggsradius=10000&ggslimit=50&format=json"
        
        guard let url = URL(string: urlString) else { return }
        
        if let data = try? Data(contentsOf: url) {
            
            sightsJSON = JSON(data)
            locationManager.startUpdatingHeading() //using CoreMotion
            
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        //push all work to the main thread
        DispatchQueue.main.async {
             //add one to the heading count - if that count does NOT equal 2, exit the method.
            
            //because initial heading is often inaccurate, disregard the initial one
            self.headingCount += 1
            if self.headingCount != 2 { return }
            
            //Otherwise, store the heading, tell CL to stop sending us headings
            self.userHeading = newHeading.magneticHeading
            self.locationManager.stopUpdatingHeading()
            
            //Execute our createSights()
            self.createSights()
            
        }
    }
    
    func createSights() {
        //go over all the pages in our Wikipedia data and convert them to anchor objects
        //each anchor added to dictionary, stors anchor UUID as key and wiki page title as value
        
        //loop over wikipedia pages
        for page in sightsJSON["query"]["pages"].dictionaryValue.values {
            
            //pull out this page's coordinates and make a location from them
            let locationLat = page["coordinates"][0]["lat"].doubleValue
            let loctaionLon = page["coordinates"][0]["lon"].doubleValue
            let location = CLLocation(latitude: locationLat, longitude: loctaionLon)
            
            //calculate the distance from the user to this point, then calculate its azimuth
            let distance = Float(userLocation.distance(from: location))
            let azimuthFromUser = direction(from: userLocation, to: location)
            
            //calculate the angle from the user to that direction
            let angle = azimuthFromUser - userHeading
            let angleRadians = deg2Rad(angle)
            
            //create a horizontal rotation matrix
            let rotationHorizontal = matrix_float4x4(SCNMatrix4MakeRotation(Float(angleRadians), 1, 0, 0))
            
            //create a vertical rotation matrix
            let rotationVertical = matrix_float4x4(SCNMatrix4MakeRotation(-0.2 + Float(distance / 600), 0, 1, 0))
            
            //combine the horizontal and vertical matrices, then combine that with camera transform
            let rotation = simd_mul(rotationHorizontal, rotationVertical)
            guard let sceneView = self.view as? ARSKView else { return }
            guard let frame = sceneView.session.currentFrame else { return }
            let rotation2 = simd_mul(frame.camera.transform, rotation)
            
            //create a matrix that lets us position the anchor into the screen, then combine that with our combined matrix so far
            var translations = matrix_identity_float4x4
            translations.columns.3.z = -(distance / 50)
            
            let transform = simd_mul(rotation2, translations)
            
            //create a new anchor using the final matrix, then add it to our pages dictionary
            let anchor = ARAnchor(transform: transform)
            sceneView.session.add(anchor: anchor)
            pages[anchor.identifier] = page["title"].string ?? "Unknown"
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        let ac = UIAlertController(title: "Unable to find location", message: error.localizedDescription, preferredStyle: .alert)
        ac.addAction(UIAlertAction(title: "OK", style: .default, handler: nil))
        present(ac, animated: true, completion: nil)
        
        print(error.localizedDescription)
    }
    
    //MARK:- Conversion functions and calculating distances
    func direction(from p1: CLLocation, to p2: CLLocation) -> Double {
        //calc distance between longitude between point A and point B
        //calc the sine of that value
        //multiply that result by the cosine of the point B's latitude to get Y
        
        //calc the cosine of point A's latitude
        //multiply the result by the sine of point B's latitude
        //subtract from the sine of point A's lat multiplied by cosine of point B's lat multiplied  by cosine of difference in longitude of point A and point B to get X
        
        //put X and Y through atan2() to calculate final direction
        
        let lon_delta = p2.coordinate.longitude - p1.coordinate.longitude
        let y = sin(lon_delta) * cos(p2.coordinate.latitude)
        let x = cos(p1.coordinate.latitude) * sin(p2.coordinate.latitude) - sin(p1.coordinate.latitude) * cos(p2.coordinate.latitude) * cos(lon_delta)
        let radians = atan2(y, x)
        
        return rad2Deg(radians)
    }
    
    func deg2Rad(_ degrees: Double) -> Double {
        return degrees * Double.pi / 100
    }
    
    func rad2Deg(_ radians: Double) -> Double {
        return radians * 100 / Double.pi
    }
    
   
}
