#import <UIKit/UIKit.h>

NSString* requestedEpisodeId = nil;
NSString* authHeader = nil;
NSString* videoToken = nil;

%hook AVURLAsset
    - (instancetype) initWithURL:(NSURL*)url options:(NSDictionary<NSString*, id>*)options {
        NSString* requestURLString = [url absoluteString];
        
        NSMutableDictionary* updatedOptions = [options mutableCopy];
        
        if ([requestURLString hasPrefix: @"https://cr-play-service.prd.crunchyrollsvc.com/v1/manifest/"]) {
            [updatedOptions setValue: @{ @"Authorization": authHeader } forKey: @"AVURLAssetHTTPHeaderFieldsKey"];
        }
        
        return %orig(url, updatedOptions);
    }
%end

%hook NSURLSession
    - (NSURLSessionDataTask*) dataTaskWithRequest:(NSURLRequest*)request completionHandler:(void (^)(NSData* data, NSURLResponse* response, NSError* error))completionHandler {
        if ([request isKindOfClass: [NSMutableURLRequest class]]) {
            NSString* requestURLString = [[request URL] absoluteString];
            
            if ([requestURLString isEqual: @"https://www.crunchyroll.com/auth/v1/token"]) {
                NSMutableURLRequest* mutableRequest = (NSMutableURLRequest*) request;
                
                // Hardcoded new credentials
                NSString* newClientId = @"zujyohvez1ofx23euerw";
                NSString* newClientSecret = @"RthKTsp0LbPT5S1YCrEKrDj-KidnnYzl";
                
                // Format them as Base64 for the Basic Auth header
                NSString* combinedCredentials = [NSString stringWithFormat: @"%@:%@", newClientId, newClientSecret];
                NSData* credentialsData = [combinedCredentials dataUsingEncoding: NSUTF8StringEncoding];
                NSString* base64Credentials = [credentialsData base64EncodedStringWithOptions: 0];
                NSString* newAuthHeader = [NSString stringWithFormat: @"Basic %@", base64Credentials];
                
                // Forcefully replace the old Authorization header
                [mutableRequest setValue: newAuthHeader forHTTPHeaderField: @"Authorization"];
                
                // Override User-Agent to mimic Android device
                [mutableRequest setValue: @"Crunchyroll/3.113.0 Android/9 okhttp/5.3.2" forHTTPHeaderField: @"User-Agent"];
                
                // Override the request body with the custom Android parameters
                NSString* newBodyString = @"grant_type=client_id&device_id=b17bc6f2-8125-4e0e-9855-4e1f11cc2324&device_name=SM-G998B&device_type=samsung+SM-G998B";
                NSData* newBodyData = [newBodyString dataUsingEncoding: NSUTF8StringEncoding];
                [mutableRequest setHTTPBody: newBodyData];
                
            } else if (
                [requestURLString hasPrefix: @"https://www.crunchyroll.com/cms/v2/"] &&
                [requestURLString containsString: @"/crunchyroll/objects/"]
            ) {
                NSString* episodeId = [[requestURLString componentsSeparatedByString: @"/crunchyroll/objects/"][1] componentsSeparatedByString: @"?"][0];
                
                if (![episodeId containsString: @","]) {
                    requestedEpisodeId = episodeId;
                }
            } else if (
                [requestURLString hasPrefix: @"https://www.crunchyroll.com/content/v1/"]
            ) {
                authHeader = [request valueForHTTPHeaderField: @"Authorization"];
            } else if (
                [requestURLString hasPrefix: @"https://www.crunchyroll.com/cms/v2/"] &&
                [requestURLString containsString: @"/crunchyroll/videos/"] &&
                [requestURLString containsString: @"/streams"]
            ) {
                NSMutableURLRequest* mutableRequest = (NSMutableURLRequest*) request;
                
                NSString* requestedLocale = [[requestURLString componentsSeparatedByString: @"locale="][1] componentsSeparatedByString: @"&"][0];
                
                [mutableRequest setValue: authHeader forHTTPHeaderField: @"Authorization"];
                
                [mutableRequest setURL: [NSURL URLWithString: [NSString
                    stringWithFormat: @"https://cr-play-service.prd.crunchyrollsvc.com/v1/%@/ios/iphone/play?queue=false",
                    requestedEpisodeId
                ]]];
                
                id completionBlock = ^(NSData* originalResponseData, NSURLResponse* response, NSError* error) {
                    NSString* originalResponseString = [[NSString alloc] initWithData: originalResponseData encoding: NSUTF8StringEncoding];
                    
                    if ([originalResponseString containsString: @"\"error\":"]) {
                        completionHandler(originalResponseData, response, error);
                        return;
                    }
                    
                    NSString* streamURL = [[[originalResponseString componentsSeparatedByString: @"}},\"token\":\""][1] componentsSeparatedByString: @"\"url\":\""][1] componentsSeparatedByString: @"\""][0];
                    
                    NSString* updatedSubtitlesDictString = [[[originalResponseString componentsSeparatedByString: @"\"subtitles\":"][1] componentsSeparatedByString: @"},\"token\""][0] stringByReplacingOccurrencesOfString: @"\"language\":" withString: @"\"locale\":"];
                    
                    videoToken = [[originalResponseString componentsSeparatedByString: @",\"token\":\""][1] componentsSeparatedByString: @"\""][0];
                    
                    NSString* updatedResponseStreamContentString = [NSString
                        stringWithFormat: @"{ \"%@\": { \"hardsub_locale\": \"%@\", \"url\": \"%@\" }, \"ja-JP\": { \"hardsub_locale\": \"ja-JP\", \"url\": \"%@\" }, \"\": { \"hardsub_locale\": \"\", \"url\": \"%@\", \"vcodec\": \"h264\" } }",
                        requestedLocale,
                        requestedLocale,
                        streamURL,
                        streamURL,
                        streamURL
                    ];
                    
                    NSString *updatedResponseString = [NSString
                        stringWithFormat: @"{ \"__class__\": \"video_streams\", \"__actions__\": {}, \"__href__\": \"/cms/v2/US/M3/crunchyroll/videos/LOL/streams\", \"__resource_key__\": \"cms:/videos/LOL/streams\", \"__links__\": { \"resource\": { \"href\": \"/cms/v2/US/M3/crunchyroll/videos/LOL/streams\" } }, \"media_id\": \"%@\", \"audio_locale\": \"ja-JP\", \"streams\": { \"drm_adaptive_hls\": %@ }, \"subtitles\": %@ }, \"captions\": {}, \"closed_captions\": {}, \"bifs\": [], \"versions\": [ { \"audio_locale\": \"ja-JP\", \"guid\": \"LOL\", \"is_premium_only\": false, \"media_guid\": \"LOL\", \"original\": true, \"season_guid\": \"LOL\", \"variant\": \"\" } ], \"QoS\": { \"region\": \"lol\", \"cloudFrontRequestId\": \"lol\", \"lambdaRunTime\": 5 } }",
                        requestedEpisodeId,
                        updatedResponseStreamContentString,
                        updatedSubtitlesDictString
                    ];
                    NSData* updatedResponseData = [updatedResponseString dataUsingEncoding: NSUTF8StringEncoding];
                    
                    completionHandler(updatedResponseData, response, error);
                };
                
                return %orig(mutableRequest, completionBlock);
            } else if (
                [requestURLString hasPrefix: @"https://cr-play-service.prd.crunchyrollsvc.com/v1/manifest/"]
            ) {
                NSMutableURLRequest* mutableRequest = (NSMutableURLRequest*) request;
                
                [mutableRequest setValue: authHeader forHTTPHeaderField: @"Authorization"];
            } else if (
                [requestURLString hasPrefix: @"https://pl.crunchyroll.com/drm/v1/fairplay?"]
            ) {
                NSMutableURLRequest* mutableRequest = (NSMutableURLRequest*) request;
                
                NSString* urlParams = [requestURLString componentsSeparatedByString: @"?"][1];
                
                [mutableRequest setURL: [NSURL URLWithString: [NSString
                    stringWithFormat: @"https://cr-license-proxy.prd.crunchyrollsvc.com/v1/license/fairPlay?%@",
                    urlParams
                ]]];
                
                [mutableRequest setValue: authHeader forHTTPHeaderField: @"Authorization"];
                
                [mutableRequest setValue: requestedEpisodeId forHTTPHeaderField: @"X-Cr-Content-Id"];
                [mutableRequest setValue: videoToken forHTTPHeaderField: @"X-Cr-Video-Token"];
            }
        }
        
        return %orig;
    }
%end
