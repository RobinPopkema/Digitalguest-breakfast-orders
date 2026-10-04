#include "breakfast_native.h"
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <commdlg.h>
#include <wincrypt.h>
#include <string>
#include <vector>

void RegisterBreakfastNative(flutter::BinaryMessenger* messenger, HWND window) {
  flutter::MethodChannel<flutter::EncodableValue> channel(messenger,"no.breakfast.orders/windows",&flutter::StandardMethodCodec::GetInstance());
  channel.SetMethodCallHandler([window](const auto& call, auto result) {
    const auto& method = call.method_name();
    if (method == "protect" || method == "unprotect") {
      const auto* bytes = call.arguments() ? std::get_if<std::vector<uint8_t>>(call.arguments()) : nullptr;
      if (!bytes || bytes->empty()) { result->Error("invalid", "Empty credential data."); return; }
      DATA_BLOB input{static_cast<DWORD>(bytes->size()),const_cast<BYTE*>(bytes->data())}, output{};
      BOOL ok = method == "protect" ? CryptProtectData(&input,L"Breakfast Orders Flutter",nullptr,nullptr,nullptr,CRYPTPROTECT_UI_FORBIDDEN,&output) : CryptUnprotectData(&input,nullptr,nullptr,nullptr,nullptr,CRYPTPROTECT_UI_FORBIDDEN,&output);
      if (!ok) { result->Error("credential", "Windows could not access the protected password. Re-enter it for this Windows account."); return; }
      std::vector<uint8_t> value(output.pbData,output.pbData + output.cbData);
      SecureZeroMemory(output.pbData,output.cbData);LocalFree(output.pbData);
      result->Success(flutter::EncodableValue(value));
      SecureZeroMemory(value.data(),value.size());
      return;
    }
    if (method == "openFile" || method == "saveFile") {
      wchar_t path[32768] = L"breakfast-orders-backup.json";
      OPENFILENAMEW dialog{};dialog.lStructSize=sizeof(dialog);dialog.hwndOwner=window;
      dialog.lpstrFile=path;dialog.nMaxFile=32768;
      dialog.lpstrFilter=L"Breakfast Orders JSON\0*.json\0All files\0*.*\0";
      dialog.lpstrDefExt=L"json";
      dialog.Flags=OFN_EXPLORER | OFN_NOCHANGEDIR | OFN_PATHMUSTEXIST | (method=="saveFile" ? OFN_OVERWRITEPROMPT : OFN_FILEMUSTEXIST);
      BOOL ok=method=="saveFile" ? GetSaveFileNameW(&dialog) : GetOpenFileNameW(&dialog);
      if (!ok) { if (CommDlgExtendedError()) result->Error("dialog","Could not open the file dialog.");else result->Success();return; }
      int size=WideCharToMultiByte(CP_UTF8,0,path,-1,nullptr,0,nullptr,nullptr);
      std::string utf8(static_cast<size_t>(size),'\0');
      WideCharToMultiByte(CP_UTF8,0,path,-1,utf8.data(),size,nullptr,nullptr);utf8.pop_back();
      result->Success(flutter::EncodableValue(utf8));return;
    }
    result->NotImplemented();
  });
}
