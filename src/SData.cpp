/*
 *      Copyright (C) 2015  Jamal Edey
 *      http://www.kenshisoft.com/
 *
 *  This program is free software; you can redistribute it and/or
 *  modify it under the terms of the GNU General Public License
 *  as published by the Free Software Foundation; either version 2
 *  of the License, or (at your option) any later version.
 *
 *  This program is distributed in the hope that it will be useful,
 *  but WITHOUT ANY WARRANTY; without even the implied warranty of
 *  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 *  GNU General Public License for more details.
 *
 *  You should have received a copy of the GNU General Public License
 *  along with Kodi; if not, write to the Free Software
 *  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
 *
 *  http://www.gnu.org/licenses/old-licenses/gpl-2.0.html
 *
 */

#include "SData.h"

#include <cmath>

#include "tinyxml.h"
#include "platform/os.h"
#include "platform/util/util.h"

#include "libstalkerclient/itv.h"
#include "libstalkerclient/util.h"
#include "SAPI.h"
#include "Utils.h"

using namespace ADDON;

SData::SData(void)
{
  m_bInitedApi            = false;
  m_bDidHandshake         = false;
  m_bLoadedProfile        = false;
  m_bInitialized          = false;
  m_bGetEpgInfoAttempted  = false;
  m_watchdog              = NULL;
  m_xmltv                 = new XMLTV;
}

SData::~SData(void)
{
  if (m_watchdog && !m_watchdog->StopThread())
    XBMC->Log(LOG_DEBUG, "%s: %s", __FUNCTION__, "failed to stop Watchdog");
  
  m_channelGroups.clear();
  m_channels.clear();
  
  SAFE_DELETE(m_watchdog);
  SAFE_DELETE(m_xmltv);
}

std::string SData::GetFilePath(std::string strPath, bool bUserPath)
{
  return (bUserPath ? g_strUserPath : g_strClientPath) + PATH_SEPARATOR_CHAR + strPath;
}

bool SData::LoadCache()
{
  std::string strUCacheFile;
  bool bUCacheFileExists;
  std::string strCacheFile;
  TiXmlDocument xml_doc;
  TiXmlElement *pRootElement = NULL;
  TiXmlElement *pTokenElement = NULL;

  strUCacheFile = GetFilePath("cache.xml");
  bUCacheFileExists = XBMC->FileExists(strUCacheFile.c_str(), false);
  strCacheFile = bUCacheFileExists ? strUCacheFile : GetFilePath("cache.xml", false);

  if (!xml_doc.LoadFile(strCacheFile)) {
    XBMC->Log(LOG_ERROR, "failed to load: %s", strCacheFile.c_str());
    return false;
  }

  if (!bUCacheFileExists) {
    XBMC->Log(LOG_DEBUG, "saving cache to user path");

    if (!xml_doc.SaveFile(strUCacheFile)) {
      XBMC->Log(LOG_ERROR, "failed to save %s", strUCacheFile.c_str());
      return false;
    }

    XBMC->Log(LOG_DEBUG, "reloading cache from user path");
    return LoadCache();
  }

  pRootElement = xml_doc.RootElement();
  if (strcmp(pRootElement->Value(), "cache") != 0) {
    XBMC->Log(LOG_ERROR, "invalid xml doc. root tag 'cache' not found");
    return false;
  }
  
  pTokenElement = pRootElement->FirstChildElement("token");
  if (!pTokenElement)
    XBMC->Log(LOG_DEBUG, "\"token\" element not found");
  else if (pTokenElement->GetText())
    SC_STR_SET(m_identity.token, pTokenElement->GetText());

  XBMC->Log(LOG_DEBUG, "%s: token=%s", __FUNCTION__, m_identity.token);

  return true;
}

bool SData::SaveCache()
{
  std::string strCacheFile;
  TiXmlDocument xml_doc;
  TiXmlElement *pRootElement = NULL;
  TiXmlElement *pTokenElement = NULL;

  strCacheFile = GetFilePath("cache.xml");

  if (!xml_doc.LoadFile(strCacheFile)) {
    XBMC->Log(LOG_ERROR, "failed to load \"%s\"", strCacheFile.c_str());
    return false;
  }

  pRootElement = xml_doc.RootElement();
  if (strcmp(pRootElement->Value(), "cache") != 0) {
    XBMC->Log(LOG_ERROR, "invalid xml doc. root tag 'cache' not found");
    return false;
  }

  pTokenElement = pRootElement->FirstChildElement("token");
  pTokenElement->Clear();
  pTokenElement->LinkEndChild(new TiXmlText(m_identity.token));

  strCacheFile = GetFilePath("cache.xml");
  if (!xml_doc.SaveFile(strCacheFile)) {
    XBMC->Log(LOG_ERROR, "failed to save \"%s\"", strCacheFile.c_str());
    return false;
  }

  return true;
}

bool SData::InitAPI()
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  m_bInitedApi = false;

  if (!SAPI::Init()) {
    XBMC->Log(LOG_ERROR, "%s: failed to init api", __FUNCTION__);
    return false;
  }

  m_bInitedApi = true;

  return true;
}

bool SData::DoHandshake()
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  Json::Value parsed;

  m_bDidHandshake = false;

  if (!SAPI::Handshake(m_identity, parsed)) {
    XBMC->Log(LOG_ERROR, "%s: Handshake failed", __FUNCTION__);
    return false;
  }
  
  if (parsed["js"].isMember("token"))
    SC_STR_SET(m_identity.token, parsed["js"]["token"].asCString());

  XBMC->Log(LOG_DEBUG, "%s: token=%s", __FUNCTION__, m_identity.token);
  
  if (parsed["js"].isMember("not_valid"))
    m_identity.valid_token = !Utils::GetIntFromJsonValue(parsed["js"]["not_valid"]);

  m_bDidHandshake = true;

  return true;
}

bool SData::DoAuth()
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  Json::Value parsed;
  bool result(false);
  
  if (!SAPI::DoAuth(m_identity, parsed)) {
    XBMC->Log(LOG_ERROR, "%s: DoAuth failed", __FUNCTION__);
    return false;
  }
  
  if (parsed.isMember("js"))
    result = parsed["js"].asBool();

  return result;
}

bool SData::LoadProfile(bool bAuthSecondStep)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  Json::Value parsed;

  m_bLoadedProfile = false;

  if (!SAPI::GetProfile(m_identity, bAuthSecondStep, parsed)) {
    XBMC->Log(LOG_ERROR, "%s: GetProfile failed", __FUNCTION__);
    return false;
  }
  
  sc_stb_profile_defaults(&m_profile);
  
  if (parsed["js"].isMember("store_auth_data_on_stb"))
    m_profile.store_auth_data_on_stb = !!Utils::GetIntFromJsonValue(parsed["js"]["store_auth_data_on_stb"]);
  
  if (parsed["js"].isMember("status"))
    m_profile.status = Utils::GetIntFromJsonValue(parsed["js"]["status"]);
  
  if (parsed["js"].isMember("msg"))
    SC_STR_SET(m_profile.msg, parsed["js"]["msg"].asCString());
  
  if (parsed["js"].isMember("block_msg"))
    SC_STR_SET(m_profile.block_msg, parsed["js"]["block_msg"].asCString());
  
  if (parsed["js"].isMember("watchdog_timeout"))
    m_profile.watchdog_timeout = Utils::GetIntFromJsonValue(parsed["js"]["watchdog_timeout"]);
  
  if (parsed["js"].isMember("timeslot"))
    m_profile.timeslot = Utils::GetDoubleFromJsonValue(parsed["js"]["timeslot"]);

  XBMC->Log(LOG_DEBUG, "%s: timeslot=%f", __FUNCTION__, m_profile.timeslot);
  
  if (m_profile.store_auth_data_on_stb && !SaveCache())
    return false;
  
  switch (m_profile.status) {
    case 0:
      m_bLoadedProfile = true;
      break;
    case 2:
      if (!DoAuth()) {
        XBMC->QueueNotification(QUEUE_ERROR, "Authentication failed.");
        return false;
      }
      
      return LoadProfile(true);
    case 1:
    default:
      XBMC->Log(LOG_ERROR, "%s: status=%i | msg=%s | block_msg=%s",
        __FUNCTION__, m_profile.status, m_profile.msg, m_profile.block_msg);
      return false;
  }

  return true;
}

bool SData::Initialize()
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  m_bInitialized = false;

  if (!m_bInitedApi && !InitAPI())
    return m_bInitialized;
  
  if (!m_bDidHandshake && !DoHandshake())
    return m_bInitialized;

  if (!m_bLoadedProfile && !LoadProfile())
    return m_bInitialized;
  
  if (!m_watchdog)
    m_watchdog = new CWatchdog((int)m_profile.timeslot, m_identity);
    
  if (m_watchdog && !m_watchdog->IsRunning() && !m_watchdog->CreateThread())
    XBMC->Log(LOG_DEBUG, "%s: %s", __FUNCTION__, "failed to start Watchdog");
  
  m_bInitialized = true;

  return m_bInitialized;
}

int SData::ParseEPG(Json::Value &parsed, time_t iStart, time_t iEnd, int iChannelNumber, ADDON_HANDLE handle)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  time_t iStartTimestamp;
  time_t iStopTimestamp;
  int iEntriesTransfered(0);

  for (Json::Value::iterator it = parsed.begin(); it != parsed.end(); ++it) {
    iStartTimestamp = Utils::GetIntFromJsonValue((*it)["start_timestamp"]);
    iStopTimestamp = Utils::GetIntFromJsonValue((*it)["stop_timestamp"]);

    if (!(iStartTimestamp > iStart && iStopTimestamp < iEnd)) {
      continue;
    }

    EPG_TAG tag;
    memset(&tag, 0, sizeof(EPG_TAG));

    tag.iUniqueBroadcastId = Utils::GetIntFromJsonValue((*it)["id"]);
    tag.strTitle = (*it)["name"].asCString();
    tag.iChannelNumber = iChannelNumber;
    tag.startTime = iStartTimestamp;
    tag.endTime = iStopTimestamp;
    tag.strPlot = (*it)["descr"].asCString();

    PVR->TransferEpgEntry(handle, &tag);
    iEntriesTransfered++;
  }
  
  return iEntriesTransfered;
}

int SData::ParseEPGXMLTV(int iChannelNumber, std::string &strChannelName, time_t iStart, time_t iEnd, ADDON_HANDLE handle)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);
  
  std::string strChanNum;
  Channel *chan = NULL;
  int iEntriesTransfered(0);
  
  strChanNum = Utils::ToString(iChannelNumber);
  
  chan = m_xmltv->GetChannelById(strChanNum);
  if (!chan)
    chan = m_xmltv->GetChannelByDisplayName(strChannelName);
  
  if (!chan) {
    XBMC->Log(LOG_DEBUG, "%s: channel \"%s\" not found", __FUNCTION__, strChanNum.c_str());
    return iEntriesTransfered;
  }
  
  for (std::vector<Programme>::iterator it = chan->programmes.begin(); it != chan->programmes.end(); ++it) {
    if (!(it->start > iStart && it->stop < iEnd))
      continue;

    EPG_TAG tag;
    memset(&tag, 0, sizeof(EPG_TAG));
    
    std::vector<Credit> cast;
    std::vector<Credit> cast2;
    cast = XMLTV::FilterCredits(it->credits, ACTOR);
    Utils::ConcatenateVectors(cast, (cast2 = XMLTV::FilterCredits(it->credits, GUEST)));
    Utils::ConcatenateVectors(cast, (cast2 = XMLTV::FilterCredits(it->credits, PRESENTER)));

    tag.iUniqueBroadcastId = it->iBroadcastId;
    tag.strTitle = it->strTitle.c_str();
    tag.iChannelNumber = iChannelNumber;
    tag.startTime = it->start;
    tag.endTime = it->stop;
    tag.strPlot = it->strDesc.c_str();
    tag.strCast = Utils::ConcatenateStringList(XMLTV::StringListForCreditType(cast)).c_str();
    tag.strDirector = Utils::ConcatenateStringList(XMLTV::StringListForCreditType(it->credits, DIRECTOR)).c_str();
    tag.strWriter = Utils::ConcatenateStringList(XMLTV::StringListForCreditType(it->credits, WRITER)).c_str();
    tag.iYear = Utils::StringToInt(it->strDate.substr(0, 4)); // year only
    tag.strIconPath = it->strIcon.c_str();
    tag.iGenreType = m_xmltv->EPGGenreByCategory(it->categories);
    if (tag.iGenreType == EPG_GENRE_USE_STRING)
      tag.strGenreDescription = Utils::ConcatenateStringList(it->categories).c_str();
    tag.firstAired = it->previouslyShown;
    tag.iStarRating = Utils::StringToInt(it->strStarRating.substr(0, 1)); // numerator only
    tag.iEpisodeNumber = it->iEpisodeNumber;
    tag.strEpisodeName = it->strSubTitle.c_str();
    
    PVR->TransferEpgEntry(handle, &tag);
    iEntriesTransfered++;
  }
  
  return iEntriesTransfered;
}

bool SData::LoadEPGForChannel(SChannel &channel, time_t iStart, time_t iEnd, ADDON_HANDLE handle)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  uint32_t iPeriod;
  Scope scope;
  std::string xmltvPath;
  std::string strChannelId;
  int iEntriesTransfered(0);

  iPeriod = (iEnd - iStart) / 3600;
  
  if (g_iXmltvScope == REMOTE_URL) {
    scope = REMOTE;
    xmltvPath = g_strXmltvUrl;
  } else {
    scope = LOCAL;
    xmltvPath = g_strXmltvPath;
  }

  if ((g_iGuidePreference != XMLTV_ONLY)
    && !m_bGetEpgInfoAttempted)
  {
    m_bGetEpgInfoAttempted = true;
    
    if (!SAPI::GetEPGInfo(iPeriod, m_identity, m_epgData))
      XBMC->Log(LOG_ERROR, "%s: GetEPGInfo failed", __FUNCTION__);
  }
  
  if ((g_iGuidePreference != PROVIDER_ONLY) && !xmltvPath.empty()
    && m_xmltv && !m_xmltv->bParseAttempted && !m_xmltv->Parse(scope, xmltvPath))
  {
    XBMC->Log(LOG_ERROR, "%s: XMLTV Parse failed", __FUNCTION__);
  }
  
  strChannelId = Utils::ToString(channel.iChannelId);
  
  switch (g_iGuidePreference) {
    case PREFER_PROVIDER:
    case PROVIDER_ONLY:
      if (!m_epgData.empty())
        iEntriesTransfered = ParseEPG(m_epgData["js"]["data"][strChannelId.c_str()], iStart, iEnd, channel.iChannelNumber, handle);
      
      if (g_iGuidePreference == PROVIDER_ONLY)
        break;
      
      if (iEntriesTransfered == 0)
        ParseEPGXMLTV(channel.iChannelNumber, channel.strChannelName, iStart, iEnd, handle);
      
      break;
    case PREFER_XMLTV:
    case XMLTV_ONLY:
      iEntriesTransfered = ParseEPGXMLTV(channel.iChannelNumber, channel.strChannelName, iStart, iEnd, handle);
      
      if (g_iGuidePreference == XMLTV_ONLY)
        break;
      
      if (!m_epgData.empty() && iEntriesTransfered == 0)
        ParseEPG(m_epgData["js"]["data"][strChannelId.c_str()], iStart, iEnd, channel.iChannelNumber, handle);
      
      break;
  }

  return true;
}

bool SData::ParseChannelGroups(Json::Value &parsed)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  try {
    for (Json::Value::iterator it = parsed["js"].begin(); it != parsed["js"].end(); ++it) {
      SChannelGroup channelGroup;
      channelGroup.strGroupName = (*it)["title"].asString();
      channelGroup.strGroupName[0] = toupper(channelGroup.strGroupName[0]);
      channelGroup.bRadio = false;
      channelGroup.strId = (*it)["id"].asString();
      channelGroup.strAlias = (*it)["alias"].asString();

      m_channelGroups.push_back(channelGroup);

      XBMC->Log(LOG_DEBUG, "%s: %s - %s",
        __FUNCTION__, channelGroup.strId.c_str(), channelGroup.strGroupName.c_str());
    }
  }
  catch (...) {
    return false;
  }

  return true;
}

bool SData::LoadChannelGroups()
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  if (!m_bInitialized && !Initialize())
    return false;

  Json::Value parsed;

  // genres are channel groups
  if (!SAPI::GetGenres(m_identity, parsed) || !ParseChannelGroups(parsed)) {
    XBMC->Log(LOG_ERROR, "%s: GetGenres|ParseChannelGroups failed", __FUNCTION__);
    return false;
  }

  return true;
}

int SData::GetChannelId(const char * strChannelName, const char * strNumber)
{
  std::string concat(strChannelName);
  concat.append(strNumber);

  const char* strString = concat.c_str();
  int iId = 0;
  int c;
  while (c = *strString++)
    iId = ((iId << 5) + iId) + c; /* iId * 33 + c */

  return abs(iId);
}

bool SData::ParseChannels(Json::Value &parsed)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  try {
    for (Json::Value::iterator it = parsed["js"]["data"].begin(); it != parsed["js"]["data"].end(); ++it) {
      SChannel channel;
      channel.iUniqueId = GetChannelId((*it)["name"].asCString(), (*it)["number"].asCString());
      channel.bRadio = false;
      channel.iChannelNumber = Utils::StringToInt((*it)["number"].asString());
      channel.strChannelName = (*it)["name"].asString();

      // "pvr://stream/" causes GetLiveStreamURL to be called
      channel.strStreamURL = "pvr://stream/" + Utils::ToString(channel.iUniqueId);

      std::string strLogo = (*it)["logo"].asString();
      channel.strIconPath = strLogo.length() == 0 ? "" : std::string(g_strApiBasePath + SC_ITV_LOGO_PATH_320 + strLogo);

      channel.iChannelId = Utils::GetIntFromJsonValue((*it)["id"]);
      channel.strCmd = (*it)["cmd"].asString();
      channel.strTvGenreId = (*it)["tv_genre_id"].asString();
      channel.bUseHttpTmpLink = !!Utils::GetIntFromJsonValue((*it)["use_http_tmp_link"]);
      channel.bUseLoadBalancing = !!Utils::GetIntFromJsonValue((*it)["use_load_balancing"]);

      m_channels.push_back(channel);

      XBMC->Log(LOG_DEBUG, "%s: %d - %s", __FUNCTION__, channel.iChannelNumber, channel.strChannelName.c_str());
    }
  }
  catch (...) {
    return false;
  }
  
  return true;
}

bool SData::LoadChannels()
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  if (!m_bInitialized && !Initialize())
    return false;

  Json::Value parsed;
  int iGenre = 10;
  uint32_t iCurrentPage = 1;
  uint32_t iMaxPages = 1;

  if (!SAPI::GetAllChannels(m_identity, parsed) || !ParseChannels(parsed)) {
    XBMC->Log(LOG_ERROR, "%s: GetAllChannels failed", __FUNCTION__);
    return false;
  }

  parsed.clear();

  while (iCurrentPage <= iMaxPages) {
    if (!SAPI::GetOrderedList(iGenre, iCurrentPage, m_identity, parsed) || !ParseChannels(parsed)) {
      XBMC->Log(LOG_ERROR, "%s: GetOrderedList failed", __FUNCTION__);
      return false;
    }

    int iTotalItems = Utils::GetIntFromJsonValue(parsed["js"]["total_items"]);
    int iMaxPageItems = Utils::GetIntFromJsonValue(parsed["js"]["max_page_items"]);
    iMaxPages = static_cast<uint32_t>(ceil((double)iTotalItems / iMaxPageItems));

    iCurrentPage++;

    XBMC->Log(LOG_DEBUG, "%s: iTotalItems: %d | iMaxPageItems: %d | iCurrentPage: %d | iMaxPages: %d",
      __FUNCTION__, iTotalItems, iMaxPageItems, iCurrentPage, iMaxPages);
  }

  return true;
}

bool SData::LoadData(void)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  sc_identity_defaults(&m_identity);
  SC_STR_SET(m_identity.mac, g_strMac.c_str());
  SC_STR_SET(m_identity.time_zone, g_strTimeZone.c_str());
  SC_STR_SET(m_identity.token, g_strToken.c_str());
  SC_STR_SET(m_identity.login, g_strLogin.c_str());
  SC_STR_SET(m_identity.password, g_strPassword.c_str());
  SC_STR_SET(m_identity.serial_number, g_strSerialNumber.c_str());
  SC_STR_SET(m_identity.device_id, g_strDeviceId.c_str());
  SC_STR_SET(m_identity.device_id2, g_strDeviceId2.c_str());
  SC_STR_SET(m_identity.signature, g_strSignature.c_str());

  // skip handshake if token setting was set
  if (strlen(m_identity.token) > 0)
    m_bDidHandshake = true;
  else if (!LoadCache())
    return false;

  return true;
}

PVR_ERROR SData::GetEPGForChannel(ADDON_HANDLE handle, const PVR_CHANNEL &channel, time_t iStart, time_t iEnd)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  SChannel *thisChannel = NULL;

  for (unsigned int iChannelPtr = 0; iChannelPtr < m_channels.size(); iChannelPtr++) {
    thisChannel = &m_channels.at(iChannelPtr);

    if (thisChannel->iUniqueId == (int)channel.iUniqueId) {
      break;
    }
  }

  if (!thisChannel) {
    XBMC->Log(LOG_ERROR, "%s: channel not found", __FUNCTION__);
    return PVR_ERROR_SERVER_ERROR;
  }

  XBMC->Log(LOG_DEBUG, "%s: time range: %d - %d | %d - %s",
    __FUNCTION__, iStart, iEnd, thisChannel->iChannelNumber, thisChannel->strChannelName.c_str());

  if (!LoadEPGForChannel(*thisChannel, iStart, iEnd, handle)) {
    return PVR_ERROR_SERVER_ERROR;
  }

  return PVR_ERROR_NO_ERROR;
}

int SData::GetChannelGroupsAmount(void)
{
  return m_channelGroups.size();
}

PVR_ERROR SData::GetChannelGroups(ADDON_HANDLE handle, bool bRadio)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  if (bRadio) {
    return PVR_ERROR_NO_ERROR;
  }

  if (!LoadChannelGroups()) {
    XBMC->QueueNotification(QUEUE_ERROR, "Unable to load channel groups.");
    return PVR_ERROR_SERVER_ERROR;
  }

  for (std::vector<SChannelGroup>::iterator group = m_channelGroups.begin(); group != m_channelGroups.end(); ++group) {
    // exclude group id '*' (all)
    if (group->strId.compare("*") == 0)
      continue;

    PVR_CHANNEL_GROUP tag;
    memset(&tag, 0, sizeof(tag));

    strncpy(tag.strGroupName, group->strGroupName.c_str(), sizeof(tag.strGroupName) - 1);
    tag.bIsRadio = group->bRadio;

    PVR->TransferChannelGroup(handle, &tag);
  }

  return PVR_ERROR_NO_ERROR;
}

PVR_ERROR SData::GetChannelGroupMembers(ADDON_HANDLE handle, const PVR_CHANNEL_GROUP &group)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  SChannelGroup *channelGroup = NULL;

  for (std::vector<SChannelGroup>::iterator it = m_channelGroups.begin(); it != m_channelGroups.end(); ++it) {
    if (strcmp(it->strGroupName.c_str(), group.strGroupName) == 0) {
      channelGroup = &(*it);
      break;
    }
  }

  if (!channelGroup) {
    XBMC->Log(LOG_ERROR, "%s: channel not found", __FUNCTION__);
    return PVR_ERROR_SERVER_ERROR;
  }

  for (std::vector<SChannel>::iterator channel = m_channels.begin(); channel != m_channels.end(); ++channel) {
    if (channel->strTvGenreId.compare(channelGroup->strId) != 0)
      continue;
    
    PVR_CHANNEL_GROUP_MEMBER tag;
    memset(&tag, 0, sizeof(tag));

    strncpy(tag.strGroupName, channelGroup->strGroupName.c_str(), sizeof(tag.strGroupName) - 1);
    tag.iChannelUniqueId = channel->iUniqueId;
    tag.iChannelNumber = channel->iChannelNumber;

    PVR->TransferChannelGroupMember(handle, &tag);
  }

  return PVR_ERROR_NO_ERROR;
}

int SData::GetChannelsAmount(void)
{
  return m_channels.size();
}

PVR_ERROR SData::GetChannels(ADDON_HANDLE handle, bool bRadio)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  if (bRadio)
    return PVR_ERROR_NO_ERROR;

  if (!LoadChannels()) {
    XBMC->QueueNotification(QUEUE_ERROR, "Unable to load channels.");
    return PVR_ERROR_SERVER_ERROR;
  }

  for (std::vector<SChannel>::iterator channel = m_channels.begin(); channel != m_channels.end(); ++channel) {
    PVR_CHANNEL tag;
    memset(&tag, 0, sizeof(tag));

    tag.iUniqueId = channel->iUniqueId;
    tag.bIsRadio = channel->bRadio;
    tag.iChannelNumber = channel->iChannelNumber;
    strncpy(tag.strChannelName, channel->strChannelName.c_str(), sizeof(tag.strChannelName) - 1);
    strncpy(tag.strStreamURL, channel->strStreamURL.c_str(), sizeof(tag.strStreamURL) - 1);
    strncpy(tag.strIconPath, channel->strIconPath.c_str(), sizeof(tag.strIconPath) - 1);
    tag.bIsHidden = false;

    PVR->TransferChannelEntry(handle, &tag);
  }

  return PVR_ERROR_NO_ERROR;
}

const char* SData::GetChannelStreamURL(const PVR_CHANNEL &channel)
{
  XBMC->Log(LOG_DEBUG, "%s", __FUNCTION__);

  SChannel *thisChannel = NULL;
  std::string strCmd;
  size_t pos;

  for (unsigned int iChannelPtr = 0; iChannelPtr < m_channels.size(); iChannelPtr++) {
    thisChannel = &m_channels.at(iChannelPtr);

    if (thisChannel->iUniqueId == (int)channel.iUniqueId)
      break;
  }

  if (!thisChannel) {
    XBMC->Log(LOG_ERROR, "%s: channel not found", __FUNCTION__);
    return "";
  }

  m_PlaybackURL.clear();

  // /c/player.js#L2198
  if (thisChannel->bUseHttpTmpLink || thisChannel->bUseLoadBalancing) {
    XBMC->Log(LOG_DEBUG, "%s: getting temp stream url", __FUNCTION__);

    Json::Value parsed;

    if (!SAPI::CreateLink(thisChannel->strCmd, m_identity, parsed)) {
      XBMC->Log(LOG_ERROR, "%s: CreateLink failed", __FUNCTION__);
      return "";
    }

    if (parsed["js"].isMember("cmd"))
      strCmd = parsed["js"]["cmd"].asString();
  }
  else {
    strCmd = thisChannel->strCmd;
  }

  // cmd format
  // (?:ffrt\d*\s|)(.*)
  if ((pos = strCmd.find(" ")) != std::string::npos)
    m_PlaybackURL = strCmd.substr(pos + 1);
  else
    m_PlaybackURL = strCmd;

  if (m_PlaybackURL.empty()) {
    XBMC->Log(LOG_ERROR, "%s: no stream url found", __FUNCTION__);
    return "";
  }
  
  /* some protocols don't strip the protocol options.
  some servers handle it, others don't. */
  //TODO other protocols may need to be excluded
  if (m_PlaybackURL.find("rtmp://") == std::string::npos)
    m_PlaybackURL += "|Connection-Timeout=" + Utils::ToString(g_iConnectionTimeout);

  XBMC->Log(LOG_DEBUG, "%s: stream url: %s", __FUNCTION__, m_PlaybackURL.c_str());

  return m_PlaybackURL.c_str();
}
