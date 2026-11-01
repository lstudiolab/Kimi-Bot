const keys=["title","modules","install","uninstall","language","status","permissions","advanced","back","enable","disable","details","choose","enabled","disabled","missing","done"];
const data={
"en-US":["Timi Settings","Modules","Install Libraries","Uninstall Libraries","Language","System Status","Permissions","Advanced","Back","Enable","Disable","Details","Choose a system","Enabled","Disabled","Library not installed","Done"],
"en-GB":["Timi Settings","Modules","Install Libraries","Uninstall Libraries","Language","System Status","Permissions","Advanced","Back","Enable","Disable","Details","Choose a system","Enabled","Disabled","Library not installed","Done"],
"bg":["Настройки на Timi","Модули","Инсталиране на библиотеки","Деинсталиране на библиотеки","Език","Състояние на системата","Разрешения","Разширени","Назад","Активиране","Деактивиране","Подробности","Изберете система","Активирано","Деактивирано","Библиотеката не е инсталирана","Готово"],
"zh-CN":["Timi 设置","模块","安装库","卸载库","语言","系统状态","权限","高级","返回","启用","停用","详情","选择系统","已启用","已停用","尚未安装库","完成"],
"zh-TW":["Timi 設定","模組","安裝程式庫","解除安裝程式庫","語言","系統狀態","權限","進階","返回","啟用","停用","詳細資料","選擇系統","已啟用","已停用","尚未安裝程式庫","完成"],
"hr":["Postavke Timi","Moduli","Instaliraj biblioteke","Deinstaliraj biblioteke","Jezik","Status sustava","Dozvole","Napredno","Natrag","Omogući","Onemogući","Pojedinosti","Odaberite sustav","Omogućeno","Onemogućeno","Biblioteka nije instalirana","Gotovo"],
"cs":["Nastavení Timi","Moduly","Instalovat knihovny","Odinstalovat knihovny","Jazyk","Stav systému","Oprávnění","Pokročilé","Zpět","Povolit","Zakázat","Podrobnosti","Vyberte systém","Povoleno","Zakázáno","Knihovna není nainstalována","Hotovo"],
"da":["Timi-indstillinger","Moduler","Installer biblioteker","Afinstaller biblioteker","Sprog","Systemstatus","Tilladelser","Avanceret","Tilbage","Aktivér","Deaktivér","Detaljer","Vælg et system","Aktiveret","Deaktiveret","Bibliotek ikke installeret","Færdig"],
"nl":["Timi-instellingen","Modules","Bibliotheken installeren","Bibliotheken verwijderen","Taal","Systeemstatus","Machtigingen","Geavanceerd","Terug","Inschakelen","Uitschakelen","Details","Kies een systeem","Ingeschakeld","Uitgeschakeld","Bibliotheek niet geïnstalleerd","Klaar"],
"fi":["Timi-asetukset","Moduulit","Asenna kirjastoja","Poista kirjastoja","Kieli","Järjestelmän tila","Oikeudet","Lisäasetukset","Takaisin","Ota käyttöön","Poista käytöstä","Tiedot","Valitse järjestelmä","Käytössä","Ei käytössä","Kirjastoa ei ole asennettu","Valmis"],
"fr":["Paramètres Timi","Modules","Installer des bibliothèques","Désinstaller des bibliothèques","Langue","État du système","Autorisations","Avancé","Retour","Activer","Désactiver","Détails","Choisir un système","Activé","Désactivé","Bibliothèque non installée","Terminé"],
"de":["Timi-Einstellungen","Module","Bibliotheken installieren","Bibliotheken deinstallieren","Sprache","Systemstatus","Berechtigungen","Erweitert","Zurück","Aktivieren","Deaktivieren","Details","System auswählen","Aktiviert","Deaktiviert","Bibliothek nicht installiert","Fertig"],
"el":["Ρυθμίσεις Timi","Μονάδες","Εγκατάσταση βιβλιοθηκών","Απεγκατάσταση βιβλιοθηκών","Γλώσσα","Κατάσταση συστήματος","Δικαιώματα","Για προχωρημένους","Πίσω","Ενεργοποίηση","Απενεργοποίηση","Λεπτομέρειες","Επιλέξτε σύστημα","Ενεργό","Ανενεργό","Η βιβλιοθήκη δεν έχει εγκατασταθεί","Ολοκληρώθηκε"],
"hi":["Timi सेटिंग्स","मॉड्यूल","लाइब्रेरी इंस्टॉल करें","लाइब्रेरी हटाएँ","भाषा","सिस्टम स्थिति","अनुमतियाँ","उन्नत","वापस","सक्षम करें","अक्षम करें","विवरण","सिस्टम चुनें","सक्षम","अक्षम","लाइब्रेरी इंस्टॉल नहीं है","हो गया"],
"hu":["Timi beállítások","Modulok","Könyvtárak telepítése","Könyvtárak eltávolítása","Nyelv","Rendszerállapot","Engedélyek","Speciális","Vissza","Engedélyezés","Letiltás","Részletek","Válassz rendszert","Engedélyezve","Letiltva","A könyvtár nincs telepítve","Kész"],
"id":["Pengaturan Timi","Modul","Pasang Pustaka","Hapus Pustaka","Bahasa","Status Sistem","Izin","Lanjutan","Kembali","Aktifkan","Nonaktifkan","Detail","Pilih sistem","Aktif","Nonaktif","Pustaka belum dipasang","Selesai"],
"it":["Impostazioni Timi","Moduli","Installa librerie","Disinstalla librerie","Lingua","Stato del sistema","Autorizzazioni","Avanzate","Indietro","Abilita","Disabilita","Dettagli","Scegli un sistema","Abilitato","Disabilitato","Libreria non installata","Completato"],
"ja":["Timi 設定","モジュール","ライブラリをインストール","ライブラリをアンインストール","言語","システム状態","権限","詳細設定","戻る","有効化","無効化","詳細","システムを選択","有効","無効","ライブラリ未インストール","完了"],
"ko":["Timi 설정","모듈","라이브러리 설치","라이브러리 제거","언어","시스템 상태","권한","고급","뒤로","활성화","비활성화","세부 정보","시스템 선택","활성화됨","비활성화됨","라이브러리가 설치되지 않음","완료"],
"lt":["Timi nustatymai","Moduliai","Įdiegti bibliotekas","Pašalinti bibliotekas","Kalba","Sistemos būsena","Leidimai","Išplėstiniai","Atgal","Įjungti","Išjungti","Išsami informacija","Pasirinkite sistemą","Įjungta","Išjungta","Biblioteka neįdiegta","Atlikta"],
"no":["Timi-innstillinger","Moduler","Installer biblioteker","Avinstaller biblioteker","Språk","Systemstatus","Tillatelser","Avansert","Tilbake","Aktiver","Deaktiver","Detaljer","Velg et system","Aktivert","Deaktivert","Biblioteket er ikke installert","Ferdig"],
"pl":["Ustawienia Timi","Moduły","Zainstaluj biblioteki","Odinstaluj biblioteki","Język","Stan systemu","Uprawnienia","Zaawansowane","Wstecz","Włącz","Wyłącz","Szczegóły","Wybierz system","Włączone","Wyłączone","Biblioteka nie jest zainstalowana","Gotowe"],
"pt-BR":["Configurações do Timi","Módulos","Instalar bibliotecas","Desinstalar bibliotecas","Idioma","Status do sistema","Permissões","Avançado","Voltar","Ativar","Desativar","Detalhes","Escolha um sistema","Ativado","Desativado","Biblioteca não instalada","Concluído"],
"ro":["Setări Timi","Module","Instalează biblioteci","Dezinstalează biblioteci","Limbă","Starea sistemului","Permisiuni","Avansat","Înapoi","Activează","Dezactivează","Detalii","Alege un sistem","Activat","Dezactivat","Biblioteca nu este instalată","Gata"],
"ru":["Настройки Timi","Модули","Установить библиотеки","Удалить библиотеки","Язык","Состояние системы","Разрешения","Дополнительно","Назад","Включить","Отключить","Подробнее","Выберите систему","Включено","Отключено","Библиотека не установлена","Готово"],
"es-ES":["Ajustes de Timi","Módulos","Instalar bibliotecas","Desinstalar bibliotecas","Idioma","Estado del sistema","Permisos","Avanzado","Volver","Activar","Desactivar","Detalles","Elige un sistema","Activado","Desactivado","Biblioteca no instalada","Hecho"],
"sv-SE":["Timi-inställningar","Moduler","Installera bibliotek","Avinstallera bibliotek","Språk","Systemstatus","Behörigheter","Avancerat","Tillbaka","Aktivera","Inaktivera","Detaljer","Välj ett system","Aktiverat","Inaktiverat","Biblioteket är inte installerat","Klart"],
"th":["การตั้งค่า Timi","โมดูล","ติดตั้งไลบรารี","ถอนการติดตั้งไลบรารี","ภาษา","สถานะระบบ","สิทธิ์","ขั้นสูง","กลับ","เปิดใช้งาน","ปิดใช้งาน","รายละเอียด","เลือกระบบ","เปิดใช้งานแล้ว","ปิดใช้งานแล้ว","ยังไม่ได้ติดตั้งไลบรารี","เสร็จสิ้น"],
"tr":["Timi Ayarları","Modüller","Kütüphaneleri Yükle","Kütüphaneleri Kaldır","Dil","Sistem Durumu","İzinler","Gelişmiş","Geri","Etkinleştir","Devre Dışı Bırak","Ayrıntılar","Bir sistem seçin","Etkin","Devre dışı","Kütüphane yüklü değil","Tamamlandı"],
"uk":["Налаштування Timi","Модулі","Установити бібліотеки","Видалити бібліотеки","Мова","Стан системи","Дозволи","Додатково","Назад","Увімкнути","Вимкнути","Докладніше","Виберіть систему","Увімкнено","Вимкнено","Бібліотеку не встановлено","Готово"],
"vi":["Cài đặt Timi","Mô-đun","Cài đặt thư viện","Gỡ cài đặt thư viện","Ngôn ngữ","Trạng thái hệ thống","Quyền","Nâng cao","Quay lại","Bật","Tắt","Chi tiết","Chọn hệ thống","Đã bật","Đã tắt","Thư viện chưa được cài đặt","Hoàn tất"]
};
const catalog=Object.fromEntries(Object.entries(data).map(([locale,values])=>[locale,Object.fromEntries(keys.map((key,index)=>[key,values[index]]))]));
export function t(store,guildId,key){const locale=store?.data?.languages?.[guildId]||"en-US";return catalog[locale]?.[key]||catalog["en-US"][key]||key;}
export const LOCALE_NAMES={"en-US":"English (US)","en-GB":"English (UK)","bg":"Български","zh-CN":"简体中文","zh-TW":"繁體中文","hr":"Hrvatski","cs":"Čeština","da":"Dansk","nl":"Nederlands","fi":"Suomi","fr":"Français","de":"Deutsch","el":"Ελληνικά","hi":"हिन्दी","hu":"Magyar","id":"Bahasa Indonesia","it":"Italiano","ja":"日本語","ko":"한국어","lt":"Lietuvių","no":"Norsk","pl":"Polski","pt-BR":"Português (Brasil)","ro":"Română","ru":"Русский","es-ES":"Español","sv-SE":"Svenska","th":"ไทย","tr":"Türkçe","uk":"Українська","vi":"Tiếng Việt"};

const phraseToKey={
 "Timi Settings":"title","Modules":"modules","Install Libraries":"install",
 "Uninstall Libraries":"uninstall","Language":"language","System Status":"status",
 "Permissions":"permissions","Advanced":"advanced","Back":"back","Enable":"enable",
 "Disable":"disable","Details":"details","Choose a system":"choose","Enabled":"enabled",
 "Disabled":"disabled","Library not installed":"missing","Done":"done"
};
export function translateText(store,guildId,value){
 if(typeof value!=="string")return value;
 let result=value;
 for(const [phrase,key] of Object.entries(phraseToKey)){
  const translated=t(store,guildId,key);
  if(translated!==phrase)result=result.split(phrase).join(translated);
 }
 return result;
}
export function translatePayload(store,guildId,payload){
 if(payload==null)return payload;
 const visit=value=>{
  if(typeof value==="string")return translateText(store,guildId,value);
  if(Array.isArray(value))return value.map(visit);
  if(value&&typeof value==="object"){
   const source=typeof value.toJSON==="function"?value.toJSON():value;
   return Object.fromEntries(Object.entries(source).map(([key,item])=>[key,visit(item)]));
  }
  return value;
 };
 return visit(payload);
}
