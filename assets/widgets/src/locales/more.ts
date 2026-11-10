const formats = {
  timeFormat: "%H:%i",
  dateFormat: "%d.%m.%Y",
  monthYearFormat: "%F %Y",
  yearFormat: "%Y",
};

const dates = (lang: string) => (options: Intl.DateTimeFormatOptions) => {
  const format = new Intl.DateTimeFormat(lang, options);
  return (date: Date) => format.format(date);
};

const calendarFormats = (lang: string) => {
  const d = dates(lang);
  return {
    timeScaleFormat: "%H:%i",
    weekScaleFormat: "%D, %j",
    monthScaleFormat: "%D",
    weekNumberFormat: "%w",
    titleDayFormat: d({ weekday: "long", day: "numeric", month: "long", year: "numeric" }),
    titleWeekFormatStart: d({ day: "numeric", month: "long" }),
    titleWeekFormatEnd: d({ day: "numeric", month: "long", year: "numeric" }),
    titleMonthFormat: "%F %Y",
    yearMonthFormat: "%F",
    agendaDayFormat: d({ weekday: "long", day: "numeric", month: "long" }),
  };
};

type Words = {
  months: string[];
  monthsShort: string[];
  days: string[];
  daysShort: string[];
  ui: Record<string, string>;
  event: Record<string, string>;
};

function build(lang: string, w: Words) {
  return {
    core: {
      lang,
      formats,
      calendar: {
        monthFull: w.months,
        monthShort: w.monthsShort,
        dayFull: w.days,
        dayShort: w.daysShort,
        hours: w.ui.hours,
        minutes: w.ui.minutes,
        done: w.ui.done,
        clear: w.ui.clear,
        today: w.ui.today,
        weekStart: 1,
        clockFormat: 24,
      },
      core: {
        ok: "OK",
        cancel: w.ui.cancel,
        select: w.ui.select,
        "No data": w.ui.noData,
        "Rows per page": w.ui.rowsPerPage,
        "Total pages": w.ui.totalPages,
      },
    },
    calendar: { eventCalendar: { ...w.event, ...calendarFormats(lang) } },
  };
}

export const pl = build("pl-PL", {
  months: ["Styczeń", "Luty", "Marzec", "Kwiecień", "Maj", "Czerwiec", "Lipiec", "Sierpień", "Wrzesień", "Październik", "Listopad", "Grudzień"],
  monthsShort: ["Sty", "Lut", "Mar", "Kwi", "Maj", "Cze", "Lip", "Sie", "Wrz", "Paź", "Lis", "Gru"],
  days: ["Niedziela", "Poniedziałek", "Wtorek", "Środa", "Czwartek", "Piątek", "Sobota"],
  daysShort: ["Nd", "Pn", "Wt", "Śr", "Cz", "Pt", "Sb"],
  ui: { hours: "Godziny", minutes: "Minuty", done: "Gotowe", clear: "Wyczyść", today: "Dziś", cancel: "Anuluj", select: "Wybierz", noData: "Brak danych", rowsPerPage: "Wierszy na stronie", totalPages: "Liczba stron" },
  event: {
    "Edit event": "Edytuj wydarzenie", "Delete event": "Usuń wydarzenie", Delete: "Usuń", Text: "Tekst",
    "Start date": "Początek", "End date": "Koniec", "All day": "Cały dzień", Repeat: "Powtarzaj", Never: "Nigdy",
    Daily: "Codziennie", Weekly: "Co tydzień", Monthly: "Co miesiąc", Yearly: "Co rok", "Every workday": "Każdy dzień roboczy",
    Custom: "Własne", Every: "Co", "day(s)": "dni", "week(s)": "tyg.", "month(s)": "mies.", "year(s)": "lat",
    Mon: "Pn", Tue: "Wt", Wed: "Śr", Thu: "Cz", Fri: "Pt", Sat: "Sb", Sun: "Nd",
    "on day %d": "dnia %d", "on the %n %d": "w %n %d", first: "pierwszy", second: "drugi", third: "trzeci", fourth: "czwarty", last: "ostatni",
    Ends: "Kończy się", After: "Po", "On date": "W dniu", "occurrence(s)": "razach",
    Day: "Dzień", Week: "Tydzień", Month: "Miesiąc", Agenda: "Agenda", Year: "Rok", Resources: "Zasoby", Timeline: "Oś czasu",
    Today: "Dziś", "Full day": "Cały dzień", Calendars: "Kalendarze", Menu: "Menu",
    "Previous period": "Poprzedni okres", "Next period": "Następny okres", "Date navigation": "Nawigacja dat",
    "Calendar controls": "Sterowanie kalendarzem", "Calendar filters": "Filtry kalendarza", Calendar: "Kalendarz", "Calendar sidebar": "Panel kalendarza",
  },
});

export const ro = build("ro-RO", {
  months: ["Ianuarie", "Februarie", "Martie", "Aprilie", "Mai", "Iunie", "Iulie", "August", "Septembrie", "Octombrie", "Noiembrie", "Decembrie"],
  monthsShort: ["Ian", "Feb", "Mar", "Apr", "Mai", "Iun", "Iul", "Aug", "Sep", "Oct", "Noi", "Dec"],
  days: ["Duminică", "Luni", "Marți", "Miercuri", "Joi", "Vineri", "Sâmbătă"],
  daysShort: ["Du", "Lu", "Ma", "Mi", "Jo", "Vi", "Sâ"],
  ui: { hours: "Ore", minutes: "Minute", done: "Gata", clear: "Șterge", today: "Azi", cancel: "Anulează", select: "Alege", noData: "Nu există date", rowsPerPage: "Rânduri pe pagină", totalPages: "Total pagini" },
  event: {
    "Edit event": "Editează evenimentul", "Delete event": "Șterge evenimentul", Delete: "Șterge", Text: "Text",
    "Start date": "Început", "End date": "Sfârșit", "All day": "Toată ziua", Repeat: "Repetă", Never: "Niciodată",
    Daily: "Zilnic", Weekly: "Săptămânal", Monthly: "Lunar", Yearly: "Anual", "Every workday": "În fiecare zi lucrătoare",
    Custom: "Personalizat", Every: "La fiecare", "day(s)": "zile", "week(s)": "săptămâni", "month(s)": "luni", "year(s)": "ani",
    Mon: "Lu", Tue: "Ma", Wed: "Mi", Thu: "Jo", Fri: "Vi", Sat: "Sâ", Sun: "Du",
    "on day %d": "în ziua %d", "on the %n %d": "în %n %d", first: "prima", second: "a doua", third: "a treia", fourth: "a patra", last: "ultima",
    Ends: "Se termină", After: "După", "On date": "La data", "occurrence(s)": "repetări",
    Day: "Zi", Week: "Săptămână", Month: "Lună", Agenda: "Agendă", Year: "An", Resources: "Resurse", Timeline: "Cronologie",
    Today: "Azi", "Full day": "Toată ziua", Calendars: "Calendare", Menu: "Meniu",
    "Previous period": "Perioada anterioară", "Next period": "Perioada următoare", "Date navigation": "Navigare după dată",
    "Calendar controls": "Comenzile calendarului", "Calendar filters": "Filtrele calendarului", Calendar: "Calendar", "Calendar sidebar": "Bara calendarului",
  },
});

export const tr = build("tr-TR", {
  months: ["Ocak", "Şubat", "Mart", "Nisan", "Mayıs", "Haziran", "Temmuz", "Ağustos", "Eylül", "Ekim", "Kasım", "Aralık"],
  monthsShort: ["Oca", "Şub", "Mar", "Nis", "May", "Haz", "Tem", "Ağu", "Eyl", "Eki", "Kas", "Ara"],
  days: ["Pazar", "Pazartesi", "Salı", "Çarşamba", "Perşembe", "Cuma", "Cumartesi"],
  daysShort: ["Paz", "Pzt", "Sal", "Çar", "Per", "Cum", "Cmt"],
  ui: { hours: "Saat", minutes: "Dakika", done: "Tamam", clear: "Temizle", today: "Bugün", cancel: "İptal", select: "Seç", noData: "Veri yok", rowsPerPage: "Sayfa başına satır", totalPages: "Toplam sayfa" },
  event: {
    "Edit event": "Etkinliği düzenle", "Delete event": "Etkinliği sil", Delete: "Sil", Text: "Metin",
    "Start date": "Başlangıç", "End date": "Bitiş", "All day": "Tüm gün", Repeat: "Tekrarla", Never: "Asla",
    Daily: "Her gün", Weekly: "Her hafta", Monthly: "Her ay", Yearly: "Her yıl", "Every workday": "Her iş günü",
    Custom: "Özel", Every: "Her", "day(s)": "gün", "week(s)": "hafta", "month(s)": "ay", "year(s)": "yıl",
    Mon: "Pzt", Tue: "Sal", Wed: "Çar", Thu: "Per", Fri: "Cum", Sat: "Cmt", Sun: "Paz",
    "on day %d": "ayın %d. günü", "on the %n %d": "%n %d", first: "ilk", second: "ikinci", third: "üçüncü", fourth: "dördüncü", last: "son",
    Ends: "Biter", After: "Sonra", "On date": "Tarihte", "occurrence(s)": "tekrar",
    Day: "Gün", Week: "Hafta", Month: "Ay", Agenda: "Ajanda", Year: "Yıl", Resources: "Kaynaklar", Timeline: "Zaman çizelgesi",
    Today: "Bugün", "Full day": "Tüm gün", Calendars: "Takvimler", Menu: "Menü",
    "Previous period": "Önceki dönem", "Next period": "Sonraki dönem", "Date navigation": "Tarih gezinmesi",
    "Calendar controls": "Takvim denetimleri", "Calendar filters": "Takvim filtreleri", Calendar: "Takvim", "Calendar sidebar": "Takvim kenar çubuğu",
  },
});
