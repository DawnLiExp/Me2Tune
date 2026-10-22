#import "TagLibBridge.h"
#import <ImageIO/ImageIO.h>
#include <taglib/mpegfile.h>
#include <taglib/flacfile.h>
#include <taglib/mp4file.h>
#include <taglib/mp4tag.h>
#include <taglib/mp4item.h>
#include <taglib/mp4coverart.h>
#include <taglib/id3v2tag.h>
#include <taglib/id3v2header.h>
#include <taglib/id3v1tag.h>
#include <taglib/textidentificationframe.h>
#include <taglib/commentsframe.h>
#include <taglib/unsynchronizedlyricsframe.h>
#include <taglib/synchronizedlyricsframe.h>
#include <taglib/attachedpictureframe.h>
#include <taglib/xiphcomment.h>
#include <taglib/apetag.h>
#include <taglib/tpropertymap.h>
#include <stdexcept>

using namespace TagLib;
namespace {
NSString *ns(const String &s) { return [NSString stringWithUTF8String:s.toCString(true)] ?: @""; }
String ts(NSString *s) { return String(s.UTF8String, String::UTF8); }
NSData *data(const ByteVector &v) { return [NSData dataWithBytes:v.data() length:v.size()]; }
ByteVector bytes(NSData *d) { return ByteVector((const char *)d.bytes, (unsigned int)d.length); }
NSArray *strings(const StringList &list) {
    NSMutableArray *a = [NSMutableArray array];
    for (const auto &s : list) [a addObject:ns(s)];
    return a;
}
NSDictionary *frameIDs() {
    return @{@"TITLE":@"TIT2", @"ARTIST":@"TPE1", @"ALBUM":@"TALB", @"ALBUMARTIST":@"TPE2",
             @"COMPOSER":@"TCOM", @"GENRE":@"TCON", @"DATE":@"TDRC", @"TRACKNUMBER":@"TRCK",
             @"TRACKTOTAL":@"TRCK", @"DISCNUMBER":@"TPOS", @"DISCTOTAL":@"TPOS",
             @"COMMENT":@"COMM", @"LYRICS":@"USLT"};
}
NSDictionary *mp4Keys() {
    return @{@"TITLE":@"©nam", @"ARTIST":@"©ART", @"ALBUM":@"©alb", @"ALBUMARTIST":@"aART",
             @"COMPOSER":@"©wrt", @"GENRE":@"©gen", @"DATE":@"©day", @"TRACKNUMBER":@"trkn",
             @"TRACKTOTAL":@"trkn", @"DISCNUMBER":@"disk", @"DISCTOTAL":@"disk",
             @"COMMENT":@"©cmt", @"LYRICS":@"©lyr"};
}
NSArray *audioProperties(AudioProperties *p) {
    if (!p) throw std::runtime_error("Missing audio properties");
    return @[@(p->lengthInMilliseconds()), @(p->sampleRate()), @(p->channels())];
}
void splitPair(NSMutableDictionary *fields, NSString *number, NSString *total) {
    NSArray *values = fields[number];
    if (values.count == 1) {
        NSArray *parts = [values[0] componentsSeparatedByString:@"/"];
        if (parts.count == 2) { fields[number] = @[parts[0]]; if (!fields[total]) fields[total] = @[parts[1]]; }
    } else if (values.count > 1) { fields[total] = values; }
}
NSMutableDictionary *id3Fields(ID3v2::Tag *tag) {
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    if (!tag) return fields;
    auto props = tag->properties();
    for (NSString *key in frameIDs()) {
        if (props.contains(ts(key))) fields[key] = strings(props[ts(key)]);
    }
    // Count individual comment/lyrics frames, including descriptions/languages hidden by PropertyMap.
    for (NSString *key in @[@"COMMENT", @"LYRICS"]) {
        NSMutableArray *values = [NSMutableArray array];
        for (auto *frame : tag->frameList([frameIDs()[key] UTF8String])) {
            if (auto *f = dynamic_cast<ID3v2::CommentsFrame *>(frame)) [values addObject:ns(f->text())];
            else if (auto *f = dynamic_cast<ID3v2::UnsynchronizedLyricsFrame *>(frame)) [values addObject:ns(f->text())];
        }
        if (values.count) fields[key] = values;
    }
    NSMutableArray *lyrics = [fields[@"LYRICS"] mutableCopy] ?: [NSMutableArray array];
    for (auto *frame : tag->frameList("SYLT")) {
        if (auto *synced = dynamic_cast<ID3v2::SynchronizedLyricsFrame *>(frame)) {
            NSMutableArray *lines = [NSMutableArray array];
            for (const auto &entry : synced->synchedText()) [lines addObject:ns(entry.text)];
            [lyrics addObject:[lines componentsJoinedByString:@"\n"]];
        }
    }
    if (lyrics.count) fields[@"LYRICS"] = lyrics;
    splitPair(fields, @"TRACKNUMBER", @"TRACKTOTAL");
    splitPair(fields, @"DISCNUMBER", @"DISCTOTAL");
    return fields;
}
void addFallback(NSMutableDictionary *fields, Tag *tag) {
    if (!tag) return;
    for (const auto &entry : tag->properties()) {
        NSString *key = ns(entry.first);
        if (frameIDs()[key]) {
            NSArray *values = strings(entry.second);
            if (!fields[key]) fields[key] = values;
            else if (values.count > 1) {
                NSMutableOrderedSet *all = [NSMutableOrderedSet orderedSetWithArray:fields[key]];
                [all addObjectsFromArray:values];
                fields[key] = all.array;
            }
        }
    }
    splitPair(fields, @"TRACKNUMBER", @"TRACKTOTAL");
    splitPair(fields, @"DISCNUMBER", @"DISCTOTAL");
}
NSDictionary *id3Inventory(ID3v2::Tag *tag) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (tag) for (const auto &entry : tag->frameListMap()) {
        NSMutableArray *frames = [NSMutableArray array];
        for (auto *f : entry.second) [frames addObject:data(f->render())];
        result[[[NSString alloc] initWithBytes:entry.first.data() length:entry.first.size() encoding:NSASCIIStringEncoding]] = frames;
    }
    return result;
}
NSDictionary *apeInventory(APE::Tag *tag) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (tag) for (const auto &entry : tag->itemListMap()) result[ns(entry.first).uppercaseString] = data(entry.second.render());
    return result;
}
NSDictionary *xiphInventory(Ogg::XiphComment *tag) {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (tag) for (const auto &entry : tag->fieldListMap()) result[ns(entry.first)] = strings(entry.second);
    return result;
}
void checkUnchanged(NSDictionary *before, NSDictionary *after, NSSet *allowed) {
    NSMutableDictionary *a = [before mutableCopy], *b = [after mutableCopy];
    for (NSString *key in allowed) { [a removeObjectForKey:key]; [b removeObjectForKey:key]; }
    if (![a isEqual:b]) {
        NSMutableSet *keys = [NSMutableSet setWithArray:a.allKeys]; [keys addObjectsFromArray:b.allKeys];
        NSMutableArray *changed = [NSMutableArray array];
        for (NSString *key in keys) if (![a[key] isEqual:b[key]]) [changed addObject:key];
        throw std::runtime_error([[NSString stringWithFormat:@"Unedited metadata changed (%@); original file was not replaced", [changed componentsJoinedByString:@", "]] UTF8String]);
    }
}
NSArray *id3Pictures(ID3v2::Tag *tag, NSInteger *primary) {
    NSMutableArray *pictures = [NSMutableArray array]; *primary = -1;
    if (tag) for (auto *frame : tag->frameList("APIC")) {
        if (auto *p = dynamic_cast<ID3v2::AttachedPictureFrame *>(frame)) {
            if (*primary < 0 || (p->type() == ID3v2::AttachedPictureFrame::FrontCover &&
                [pictures[*primary][@"type"] integerValue] != 3)) *primary = pictures.count;
            [pictures addObject:@{@"data":data(p->picture()), @"type":@(p->type())}];
        }
    }
    return pictures;
}
NSArray *flacPictures(FLAC::File &file, NSInteger *primary) {
    NSMutableArray *pictures = [NSMutableArray array]; *primary = -1;
    for (auto *p : file.pictureList()) {
        if (*primary < 0 || (p->type() == FLAC::Picture::FrontCover &&
            [pictures[*primary][@"type"] integerValue] != 3)) *primary = pictures.count;
        [pictures addObject:@{@"data":data(p->data()), @"type":@(p->type())}];
    }
    return pictures;
}
NSDictionary *readFile(NSURL *url) {
    NSString *ext = url.pathExtension.lowercaseString;
    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    NSMutableArray *readOnly = [NSMutableArray array];
    NSArray *pictures = @[], *audio; NSInteger primary = -1; BOOL writable = YES;
    if ([ext isEqual:@"mp3"]) {
        MPEG::File f(url.fileSystemRepresentation);
        if (!f.isValid()) throw std::runtime_error("Invalid MP3");
        auto *tag = f.ID3v2Tag();
        fields = id3Fields(tag);
        if (tag && !tag->frameList("SYLT").isEmpty()) [readOnly addObject:@"LYRICS"];
        addFallback(fields, f.APETag()); addFallback(fields, f.ID3v1Tag());
        pictures = id3Pictures(tag, &primary); audio = audioProperties(f.audioProperties());
    } else if ([ext isEqual:@"flac"]) {
        FLAC::File f(url.fileSystemRepresentation);
        if (!f.isValid()) throw std::runtime_error("Invalid FLAC");
        NSDictionary *raw = xiphInventory(f.xiphComment());
        for (NSString *key in frameIDs()) if (raw[key]) fields[key] = raw[key];
        for (NSArray *pair in @[@[@"COMMENT", @"DESCRIPTION"], @[@"TRACKTOTAL", @"TOTALTRACKS"], @[@"DISCTOTAL", @"TOTALDISCS"]]) {
            if (raw[pair[1]]) fields[pair[0]] = fields[pair[0]] ? [fields[pair[0]] arrayByAddingObjectsFromArray:raw[pair[1]]] : raw[pair[1]];
        }
        splitPair(fields, @"TRACKNUMBER", @"TRACKTOTAL"); splitPair(fields, @"DISCNUMBER", @"DISCTOTAL");
        NSDictionary *fallback = id3Fields(f.ID3v2Tag());
        if (f.ID3v2Tag() && !f.ID3v2Tag()->frameList("SYLT").isEmpty()) [readOnly addObject:@"LYRICS"];
        for (NSString *key in fallback) if (!fields[key]) fields[key] = fallback[key];
        addFallback(fields, f.ID3v1Tag());
        pictures = flacPictures(f, &primary); audio = audioProperties(f.audioProperties());
    } else if ([ext isEqual:@"m4a"]) {
        MP4::File f(url.fileSystemRepresentation);
        if (!f.isValid()) throw std::runtime_error("Invalid M4A");
        auto *properties = f.audioProperties();
        writable = properties && !properties->isEncrypted() &&
            (properties->codec() == MP4::Properties::AAC || properties->codec() == MP4::Properties::ALAC);
        auto *tag = f.tag();
        for (NSString *key in mp4Keys()) {
            auto item = tag->item(ts(mp4Keys()[key]));
            if (item.type() == MP4::Item::Type::StringList) fields[key] = strings(item.toStringList());
        }
        for (NSArray *pair in @[@[@"TRACKNUMBER", @"TRACKTOTAL", @"trkn"], @[@"DISCNUMBER", @"DISCTOTAL", @"disk"]]) {
            auto item = tag->item(ts(pair[2]));
            if (item.isValid()) {
                auto values = item.toIntPair();
                if (values.first) fields[pair[0]] = @[[NSString stringWithFormat:@"%d", values.first]];
                if (values.second) fields[pair[1]] = @[[NSString stringWithFormat:@"%d", values.second]];
            }
        }
        // Numeric genre is retained until this field is explicitly changed.
        if (!fields[@"GENRE"] && tag->contains("gnre")) fields[@"GENRE"] = @[ns(tag->genre())];
        NSMutableArray *art = [NSMutableArray array];
        for (const auto &p : tag->item("covr").toCoverArtList()) [art addObject:@{@"data":data(p.data()), @"type":@0}];
        pictures = art; primary = art.count ? 0 : -1; audio = audioProperties(f.audioProperties());
    } else throw std::runtime_error("Unsupported tag format");
    return @{@"fields":fields, @"pictures":pictures, @"primary":@(primary), @"audio":audio, @"writable":@(writable), @"readonly":readOnly};
}
NSString *pairValue(NSDictionary *existing, NSDictionary *patch, NSString *number, NSString *total) {
    NSString *n = patch[number] ?: [existing[number] firstObject] ?: @"";
    NSString *t = patch[total] ?: [existing[total] firstObject] ?: @"";
    return t.length ? [NSString stringWithFormat:@"%@/%@", n, t] : n;
}
void patchID3(ID3v2::Tag *tag, NSDictionary *patch, NSDictionary *visibleFields) {
    NSMutableDictionary *existing = id3Fields(tag);
    // A pair may currently come only from APE/ID3v1. Creating its ID3v2 frame
    // must preserve the unedited half instead of shadowing it with an empty value.
    for (NSString *key in @[@"TRACKNUMBER", @"TRACKTOTAL", @"DISCNUMBER", @"DISCTOTAL"]) {
        if (!existing[key] && visibleFields[key]) existing[key] = visibleFields[key];
    }
    for (NSString *key in patch) {
        NSString *frameID = frameIDs()[key]; if (!frameID) throw std::runtime_error("Unknown field");
        NSString *value = patch[key];
        if ([key hasPrefix:@"TRACK"]) value = pairValue(existing, patch, @"TRACKNUMBER", @"TRACKTOTAL");
        if ([key hasPrefix:@"DISC"]) value = pairValue(existing, patch, @"DISCNUMBER", @"DISCTOTAL");
        auto list = tag->frameList(frameID.UTF8String);
        if (value.length && list.size() == 1) {
            if (auto *f = dynamic_cast<ID3v2::CommentsFrame *>(list.front())) { f->setText(ts(value)); continue; }
            if (auto *f = dynamic_cast<ID3v2::UnsynchronizedLyricsFrame *>(list.front())) { f->setText(ts(value)); continue; }
        }
        tag->removeFrames(frameID.UTF8String);
        if ([key isEqual:@"DATE"]) for (auto id : {"TYER", "TDAT", "TIME"}) tag->removeFrames(id);
        if (!value.length) continue;
        if ([key isEqual:@"COMMENT"]) {
            auto *f = new ID3v2::CommentsFrame(String::UTF8); f->setLanguage("eng"); f->setText(ts(value)); tag->addFrame(f);
        } else if ([key isEqual:@"LYRICS"]) {
            auto *f = new ID3v2::UnsynchronizedLyricsFrame(String::UTF8); f->setLanguage("eng"); f->setText(ts(value)); tag->addFrame(f);
        } else {
            auto *f = new ID3v2::TextIdentificationFrame(frameID.UTF8String, String::UTF8); f->setText(ts(value)); tag->addFrame(f);
        }
    }
}
void patchLegacy(Tag *tag, NSDictionary *patch) {
    if (!tag) return;
    for (NSString *key in patch) {
        String value = ts(patch[key]);
        if ([key isEqual:@"TITLE"]) tag->setTitle(value);
        else if ([key isEqual:@"ARTIST"]) tag->setArtist(value);
        else if ([key isEqual:@"ALBUM"]) tag->setAlbum(value);
        else if ([key isEqual:@"COMMENT"]) tag->setComment(value);
        else if ([key isEqual:@"GENRE"]) tag->setGenre(value);
        else if ([key isEqual:@"DATE"]) tag->setYear([patch[key] intValue]);
        else if ([key isEqual:@"TRACKNUMBER"]) tag->setTrack([patch[key] intValue]);
    }
}
NSMutableSet *allowedIDs(NSDictionary *patch, BOOL art) {
    NSMutableSet *set = [NSMutableSet set];
    for (NSString *key in patch) [set addObject:frameIDs()[key]];
    if (patch[@"DATE"]) [set addObjectsFromArray:@[@"TYER", @"TDAT", @"TIME"]];
    if (art) [set addObject:@"APIC"];
    return set;
}
String imageMIME(NSData *art) {
    const unsigned char *b = (const unsigned char *)art.bytes;
    return art.length >= 8 && b[0] == 0x89 && b[1] == 0x50 ? "image/png" : "image/jpeg";
}
void writeFile(NSURL *url, NSDictionary *patch, BOOL changeArt, NSData *art) {
    NSDictionary *snapshot = readFile(url);
    if (![snapshot[@"writable"] boolValue]) throw std::runtime_error("Unsupported audio codec");
    for (NSString *key in patch) if ([snapshot[@"fields"][key] count] > 1 || [snapshot[@"readonly"] containsObject:key]) throw std::runtime_error("Multiple values are read-only");
    if (art) {
        CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)art, nullptr);
        bool valid = source && CGImageSourceGetCount(source) == 1;
        NSString *type = source ? (__bridge NSString *)CGImageSourceGetType(source) : nil;
        valid = valid && ([type isEqual:@"public.jpeg"] || [type isEqual:@"public.png"]);
        if (source) CFRelease(source);
        if (!valid) throw std::runtime_error("Artwork must be a JPEG or PNG image");
    }
    NSString *ext = url.pathExtension.lowercaseString;
    NSInteger primary = [snapshot[@"primary"] integerValue];
    if ([ext isEqual:@"mp3"]) {
        auto owner = std::make_unique<MPEG::File>(url.fileSystemRepresentation); auto &f = *owner; auto *tag = f.ID3v2Tag(true);
        auto version = tag->header()->majorVersion() == 3 ? ID3v2::v3 : ID3v2::v4;
        NSDictionary *before = id3Inventory(tag), *apeBefore = apeInventory(f.APETag());
        patchID3(tag, patch, snapshot[@"fields"]); patchLegacy(f.ID3v1Tag(), patch);
        NSMutableSet *apeAllowed = [NSMutableSet set];
        if (auto *ape = f.APETag()) {
            auto items = ape->itemListMap();
            for (const auto &entry : items) {
                NSString *key = ns(entry.first).uppercaseString;
                NSDictionary *aliases = @{@"TRACK":@"TRACKNUMBER", @"DISC":@"DISCNUMBER", @"YEAR":@"DATE", @"ALBUM ARTIST":@"ALBUMARTIST", @"TOTALTRACKS":@"TRACKTOTAL", @"TOTALDISCS":@"DISCTOTAL"};
                NSString *field = aliases[key] ?: key;
                NSString *value = patch[field];
                NSString *total = [field isEqual:@"TRACKNUMBER"] ? @"TRACKTOTAL" : ([field isEqual:@"DISCNUMBER"] ? @"DISCTOTAL" : nil);
                if (total && (value || patch[total])) {
                    NSArray *parts = [ns(entry.second.toString()) componentsSeparatedByString:@"/"];
                    NSDictionary *old = @{field:@[parts.firstObject ?: @""], total:parts.count > 1 ? @[parts[1]] : @[]};
                    value = pairValue(old, patch, field, total);
                }
                if (!value) continue;
                [apeAllowed addObject:key];
                auto item = entry.second;
                ape->removeItem(entry.first);
                if (value.length) {
                    item.setValue(ts(value));
                    ape->setItem(entry.first, item);
                }
            }
        }
        if (changeArt) {
            auto list = tag->frameList("APIC");
            ID3v2::AttachedPictureFrame *selected = nullptr; NSInteger index = 0;
            for (auto *frame : list) if (auto *p = dynamic_cast<ID3v2::AttachedPictureFrame *>(frame)) { if (index++ == primary) selected = p; }
            if (!art) { if (selected) tag->removeFrame(selected); }
            else {
                if (!selected) { selected = new ID3v2::AttachedPictureFrame; selected->setType(ID3v2::AttachedPictureFrame::FrontCover); tag->addFrame(selected); }
                selected->setPicture(bytes(art)); selected->setMimeType(imageMIME(art));
            }
        }
        if (!f.save(MPEG::File::AllTags, File::StripNone, version, File::DoNotDuplicate)) throw std::runtime_error("MP3 write failed");
        owner.reset(); // Close and flush before reopening for independent readback.
        MPEG::File check(url.fileSystemRepresentation);
        checkUnchanged(before, id3Inventory(check.ID3v2Tag()), allowedIDs(patch, changeArt));
        checkUnchanged(apeBefore, apeInventory(check.APETag()), apeAllowed);
    } else if ([ext isEqual:@"flac"]) {
        auto owner = std::make_unique<FLAC::File>(url.fileSystemRepresentation); auto &f = *owner; auto *tag = f.xiphComment(true);
        NSDictionary *before = xiphInventory(tag), *id3Before = id3Inventory(f.ID3v2Tag());
        NSMutableSet *allowed = [NSMutableSet setWithArray:patch.allKeys];
        NSMutableDictionary *normalized = [patch mutableCopy];
        for (NSArray *pair in @[@[@"TRACKNUMBER", @"TRACKTOTAL"], @[@"DISCNUMBER", @"DISCTOTAL"]]) {
            NSArray *values = before[pair[0]];
            if ((patch[pair[0]] || patch[pair[1]]) && values.count == 1 && [values[0] containsString:@"/"]) {
                for (NSString *key in pair) {
                    if (!normalized[key]) normalized[key] = [snapshot[@"fields"][key] firstObject] ?: @"";
                    [allowed addObject:key];
                }
            }
        }
        for (NSString *key in normalized) {
            tag->removeFields(ts(key)); if ([normalized[key] length]) tag->addField(ts(key), ts(normalized[key]));
            NSDictionary *aliases = @{@"COMMENT":@"DESCRIPTION", @"TRACKTOTAL":@"TOTALTRACKS", @"DISCTOTAL":@"TOTALDISCS"};
            if (NSString *alias = aliases[key]) { [allowed addObject:alias]; tag->removeFields(ts(alias)); }
        }
        if (f.ID3v2Tag()) patchID3(f.ID3v2Tag(), patch, snapshot[@"fields"]);
        patchLegacy(f.ID3v1Tag(), patch);
        if (changeArt) {
            auto list = f.pictureList(); FLAC::Picture *selected = primary >= 0 ? list[(unsigned int)primary] : nullptr;
            if (!art) { if (selected) f.removePicture(selected); }
            else {
                if (!selected) { selected = new FLAC::Picture; selected->setType(FLAC::Picture::FrontCover); f.addPicture(selected); }
                selected->setData(bytes(art)); selected->setMimeType(imageMIME(art));
                CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)art, nullptr);
                NSDictionary *props = CFBridgingRelease(CGImageSourceCopyPropertiesAtIndex(source, 0, nullptr)); CFRelease(source);
                selected->setWidth([props[(__bridge NSString *)kCGImagePropertyPixelWidth] intValue]);
                selected->setHeight([props[(__bridge NSString *)kCGImagePropertyPixelHeight] intValue]);
                selected->setColorDepth(0); selected->setNumColors(0);
            }
        }
        if (!f.save()) throw std::runtime_error("FLAC write failed");
        owner.reset();
        FLAC::File check(url.fileSystemRepresentation);
        checkUnchanged(before, xiphInventory(check.xiphComment()), allowed);
        checkUnchanged(id3Before, id3Inventory(check.ID3v2Tag()), allowedIDs(patch, NO));
    } else {
        auto owner = std::make_unique<MP4::File>(url.fileSystemRepresentation); auto &f = *owner; auto *tag = f.tag(); auto before = tag->itemMap();
        NSMutableSet *allowed = [NSMutableSet set];
        for (NSString *key in patch) {
            NSString *atom = mp4Keys()[key]; [allowed addObject:atom];
            NSString *value = patch[key];
            if ([atom isEqual:@"trkn"] || [atom isEqual:@"disk"]) {
                NSString *n = [atom isEqual:@"trkn"] ? @"TRACKNUMBER" : @"DISCNUMBER";
                NSString *t = [atom isEqual:@"trkn"] ? @"TRACKTOTAL" : @"DISCTOTAL";
                auto pair = tag->item(ts(atom)).toIntPair();
                int a = patch[n] ? [patch[n] intValue] : pair.first, b = patch[t] ? [patch[t] intValue] : pair.second;
                if (!a && !b) tag->removeItem(ts(atom)); else tag->setItem(ts(atom), MP4::Item(a,b));
            } else {
                tag->removeItem(ts(atom)); if (value.length) tag->setItem(ts(atom), MP4::Item(StringList(ts(value))));
            }
            if ([key isEqual:@"GENRE"]) { tag->removeItem("gnre"); [allowed addObject:@"gnre"]; }
        }
        if (changeArt) {
            [allowed addObject:@"covr"]; auto list = tag->item("covr").toCoverArtList();
            if (!list.isEmpty()) list.erase(list.begin());
            if (art) list.prepend(MP4::CoverArt(imageMIME(art) == "image/png" ? MP4::CoverArt::PNG : MP4::CoverArt::JPEG, bytes(art)));
            if (list.isEmpty()) tag->removeItem("covr"); else tag->setItem("covr", MP4::Item(list));
        }
        if (!f.save()) throw std::runtime_error("M4A write failed");
        owner.reset();
        MP4::File check(url.fileSystemRepresentation); auto after = check.tag()->itemMap();
        for (NSString *key in allowed) { before.erase(ts(key)); after.erase(ts(key)); }
        if (before != after) throw std::runtime_error("Unedited M4A metadata changed");
    }
    NSDictionary *after = readFile(url);
    if (![snapshot[@"audio"] isEqual:after[@"audio"]]) throw std::runtime_error("Audio properties changed");
    for (NSString *key in snapshot[@"fields"]) {
        if (!patch[key] && ![snapshot[@"fields"][key] isEqual:after[@"fields"][key]])
            throw std::runtime_error("Unedited field value changed");
    }
    for (NSString *key in patch) {
        NSString *actual = [after[@"fields"][key] firstObject] ?: @"";
        if (![actual isEqual:patch[key]]) throw std::runtime_error("Tag round-trip validation failed");
    }
    NSMutableArray *expectedPictures = [snapshot[@"pictures"] mutableCopy];
    if (changeArt) {
        if (primary >= 0) {
            if (art) expectedPictures[primary] = @{@"data":art, @"type":snapshot[@"pictures"][primary][@"type"]};
            else [expectedPictures removeObjectAtIndex:primary];
        } else if (art) [expectedPictures addObject:@{@"data":art, @"type":[ext isEqual:@"m4a"] ? @0 : @3}];
    }
    if (![expectedPictures isEqual:after[@"pictures"]]) throw std::runtime_error("Artwork preservation check failed");
}
void fail(NSError **error, const char *message, NSString *key) {
    if (error) *error = [NSError errorWithDomain:@"Me2Tune.TagLib" code:1 userInfo:@{
        NSLocalizedDescriptionKey:NSLocalizedString(key, @""),
        NSDebugDescriptionErrorKey:[NSString stringWithUTF8String:message] ?: @"Tag operation failed"}];
}
}
@implementation MTTagLibBridge
+ (NSDictionary *)readURL:(NSURL *)url error:(NSError **)error {
    try { return readFile(url); } catch (const std::exception &e) { fail(error, e.what(), @"tag_error_read"); return nil; }
}
+ (BOOL)writeURL:(NSURL *)url fields:(NSDictionary<NSString *,NSString *> *)fields artworkChanged:(BOOL)changed artwork:(NSData *)art error:(NSError **)error {
    try { writeFile(url, fields, changed, art); return YES; } catch (const std::exception &e) { fail(error, e.what(), @"tag_error_write"); return NO; }
}
@end
