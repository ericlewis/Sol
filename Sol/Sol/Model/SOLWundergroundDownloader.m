//
//  SOLWundergroundDownloader.m
//  Sol
//
//  Created by Comyar Zaheri on 8/7/13.
//  Copyright (c) 2013 Comyar Zaheri. All rights reserved.
//

#import "SOLWundergroundDownloader.h"
#import "SOLWeatherData.h"
#import "NSString+Substring.h"
#import "Climacons.h"

#define kAPI_KEY @"fcfdd93b8c9bc608d2641c408c528380"


#pragma mark - SOLWundergroundDownloader Class Extension

@interface SOLWundergroundDownloader ()
{
    /// Used by the downloader to determine the names of locations based on coordinates
    CLGeocoder  *_geocoder;
    
    /// API key
    NSString    *_key;
}
@end

#pragma mark - SOLWundergroundDownloader Implementation

@implementation SOLWundergroundDownloader

- (instancetype)init
{
    /// Instances of SOLWundergroundDownloader should be impossible to make using init
    [NSException raise:@"SOLSingletonException" format:@"SOLWundergroundDownloader cannot be initialized using init"];
    return nil;
}

#pragma mark Initializing a SOLWundergroundDownloader

+ (SOLWundergroundDownloader *)sharedDownloader
{
    static SOLWundergroundDownloader *sharedDownloader = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedDownloader = [[SOLWundergroundDownloader alloc]initWithAPIKey:kAPI_KEY];
    });
    return sharedDownloader;
}

- (instancetype)initWithAPIKey:(NSString *)key
{
    if(self = [super init]) {
        self->_key = key;
        self->_geocoder = [[CLGeocoder alloc]init];
    }
    return self;
}

#pragma mark Using a SOLWundergroundDownloader

- (void)dataForLocation:(CLLocation *)location placemark:(CLPlacemark *)placemark withTag:(NSInteger)tag completion:(SOLWeatherDataDownloadCompletion)completion
{
    /// Requests are not made if the (location and completion) or the delegate is nil
    if(!location || !completion) {
        return;
    }
    
    /// Turn on the network activity indicator in the status bar
    [[UIApplication sharedApplication]setNetworkActivityIndicatorVisible:YES];
    
    /// Get the url request
    
    [_geocoder reverseGeocodeLocation:location completionHandler:^(NSArray *placemarks, NSError *error) {
        if(placemarks) {
        NSURLRequest *request = [self urlRequestForLocation:placemarks.lastObject];
        CZLog(@"SOLWundergroundDownloader", @"Requesting URL: %@", request.URL);
        
        /// Make an asynchronous request to the url
        [NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:
         ^ (NSURLResponse * response, NSData *data, NSError *connectionError) {
             /// Report connection errors as download failures to the delegate
             if(connectionError) {
                 completion(nil, connectionError);
             } else {
                 
                 /// Serialize the downloaded JSON document and return the weather data to the delegate
                 @try {
                     NSDictionary *JSON = [self serializedData:data];
                     
                     SOLWeatherData *weatherData = [self dataFromJSON:JSON];
                     if(placemark) {
                         weatherData.placemark = placemark;
                         completion(weatherData, connectionError);
                     } else {
                         weatherData.placemark = [placemarks lastObject];
                         completion(weatherData, error);
                     }
                 }
                 
                 /// Report any failures during serialization as download failures to the delegate
                 @catch (NSException *exception) {
                     completion(nil, [NSError errorWithDomain:@"SOLWundergroundDownloader Internal State Error" code:-1 userInfo:nil]);
                 }
                 
                 /// Always turn off the network activity indicator after requests are fulfilled
                 @finally {
                     [[UIApplication sharedApplication] setNetworkActivityIndicatorVisible:NO];
                 }
             }
         }];
        }
    }];
}

- (void)dataForPlacemark:(CLPlacemark *)placemark withTag:(NSInteger)tag completion:(SOLWeatherDataDownloadCompletion)completion
{
    [self dataForLocation:placemark.location placemark:placemark withTag:tag completion:completion];
}

- (void)dataForLocation:(CLLocation *)location withTag:(NSInteger)tag completion:(SOLWeatherDataDownloadCompletion)completion
{
    [self dataForLocation:location placemark:nil withTag:tag completion:completion];
}

- (NSURLRequest *)urlRequestForLocation:(CLPlacemark *)location
{
    NSString *country_fixed = [[location.country lowercaseString] stringByReplacingOccurrencesOfString:@"the " withString:@""];
    NSString *country = [country_fixed stringByReplacingOccurrencesOfString:@" " withString:@"_"];
    static NSString *baseURL =  @"http://sochi.kimonolabs.com/api/";
    static NSString *parameters = @"countries/";
    NSString *requestURL = [NSString stringWithFormat:@"%@%@%@?fields=id,name,medals&apikey=%@", baseURL, parameters, country, _key];
    NSURL *url = [NSURL URLWithString:requestURL];
    NSURLRequest *request = [NSURLRequest requestWithURL:url];
    return request;
}

- (NSDictionary *)serializedData:(NSData *)data
{
    NSError *JSONSerializationError;
    NSDictionary *JSON = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&JSONSerializationError];
    if(JSONSerializationError) {
        [NSException raise:@"JSON Serialization Error" format:@"Failed to parse weather data"];
    }
    return JSON;
}

- (SOLWeatherData *)dataFromJSON:(NSDictionary *)JSON
{
    NSArray *currentObservation                 = [JSON             objectForKey:@"current_observation"];
    NSArray *forecast                           = [JSON             objectForKey:@"forecast"];
    NSArray *simpleforecast                     = [forecast         valueForKey:@"simpleforecast"];
    NSArray *forecastday                        = [simpleforecast   valueForKey:@"forecastday"];
    NSArray *forecastday0                       = [forecastday      objectAtIndex:0];
    NSArray *forecastday1                       = [forecastday      objectAtIndex:1];
    NSArray *forecastday2                       = [forecastday      objectAtIndex:2];
    NSArray *forecastday3                       = [forecastday      objectAtIndex:3];
    
    SOLWeatherData *data = [[SOLWeatherData alloc]init];
    
    CGFloat currentHighTemperatureF             = [[[JSON valueForKey:@"medals"] valueForKey:@"silver"] doubleValue];
    CGFloat currentHighTemperatureC             = [[[forecastday0 valueForKey:@"high"]  valueForKey:@"celsius"]doubleValue];
    
    CGFloat currentLowTemperatureF              = [[[JSON valueForKey:@"medals"] valueForKey:@"bronze"] doubleValue];
    CGFloat currentLowTemperatureC              = [[[forecastday0 valueForKey:@"low"]   valueForKey:@"celsius"]doubleValue];
    
    CGFloat currentTemperatureF                 = [[[JSON valueForKey:@"medals"] valueForKey:@"gold"] doubleValue];
    CGFloat currentTemperatureC                 = [[currentObservation valueForKey:@"temp_c"] doubleValue];
    
    data.currentSnapshot.dayOfWeek              = [[forecastday0 valueForKey:@"date"] valueForKey:@"weekday"];
    data.currentSnapshot.conditionDescription   = [NSString stringWithFormat:@"Total Medals: %@", [[JSON valueForKey:@"medals"] valueForKey:@"total"]];
    data.currentSnapshot.icon                   = [self iconForCondition:data.currentSnapshot.conditionDescription];
    data.currentSnapshot.highTemperature        = SOLTemperatureMake(currentHighTemperatureF,   currentHighTemperatureC);
    data.currentSnapshot.lowTemperature         = SOLTemperatureMake(currentLowTemperatureF,    currentLowTemperatureC);
    data.currentSnapshot.currentTemperature     = SOLTemperatureMake(currentTemperatureF,       currentTemperatureC);
    
    SOLWeatherSnapshot *forecastOne             = [[SOLWeatherSnapshot alloc]init];
    forecastOne.conditionDescription            = @"test";
    forecastOne.icon                            = [self iconForCondition:forecastOne.conditionDescription];
    forecastOne.dayOfWeek                       = [[[JSON valueForKey:@"medals"] valueForKey:@"gold"] stringValue];
    [data.forecastSnapshots addObject:forecastOne];
    
    SOLWeatherSnapshot *forecastTwo             = [[SOLWeatherSnapshot alloc]init];
    forecastTwo.conditionDescription            = [forecastday2 valueForKey:@"conditions"];
    forecastTwo.icon                            = [self iconForCondition:forecastTwo.conditionDescription];
    forecastTwo.dayOfWeek                       = [[[JSON valueForKey:@"medals"] valueForKey:@"silver"] stringValue];
    [data.forecastSnapshots addObject:forecastTwo];
    
    SOLWeatherSnapshot *forecastThree           = [[SOLWeatherSnapshot alloc]init];
    forecastThree.conditionDescription          = [forecastday3 valueForKey:@"conditions"];
    forecastThree.icon                          = [self iconForCondition:forecastThree.conditionDescription];
    forecastThree.dayOfWeek                     = [[[JSON valueForKey:@"medals"] valueForKey:@"bronze"] stringValue];
    [data.forecastSnapshots addObject:forecastThree];
    
    data.timestamp = [NSDate date];
    
    return data;
}

- (NSString *)iconForCondition:(NSString *)condition
{
    NSString *iconName = [NSString stringWithFormat:@"%c", ClimaconMoonNew];
    NSString *lowercaseCondition = [condition lowercaseString];
    
    if([lowercaseCondition contains:@"clear"]) {
        iconName = [NSString stringWithFormat:@"%c", ClimaconMoonNew];
    } else if([lowercaseCondition contains:@"cloud"]) {
        iconName = [NSString stringWithFormat:@"%c", ClimaconMoonNew];
    } else if([lowercaseCondition contains:@"drizzle"]  ||
              [lowercaseCondition contains:@"rain"]     ||
              [lowercaseCondition contains:@"thunderstorm"]) {
        iconName = [NSString stringWithFormat:@"%c", ClimaconMoonNew];
    } else if([lowercaseCondition contains:@"snow"]     ||
              [lowercaseCondition contains:@"hail"]     ||
              [lowercaseCondition contains:@"ice"]) {
        iconName = [NSString stringWithFormat:@"%c", ClimaconMoonNew];
    } else if([lowercaseCondition contains:@"fog"]      ||
              [lowercaseCondition contains:@"overcast"] ||
              [lowercaseCondition contains:@"smoke"]    ||
              [lowercaseCondition contains:@"dust"]     ||
              [lowercaseCondition contains:@"ash"]      ||
              [lowercaseCondition contains:@"mist"]     ||
              [lowercaseCondition contains:@"haze"]     ||
              [lowercaseCondition contains:@"spray"]    ||
              [lowercaseCondition contains:@"squall"]) {
        iconName = [NSString stringWithFormat:@"%c", ClimaconMoonNew];
    }
    return iconName;
}

@end
