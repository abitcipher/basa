const calendar = {
  monthFull: [
    "Січень",
    "Лютий",
    "Березень",
    "Квітень",
    "Травень",
    "Червень",
    "Липень",
    "Серпень",
    "Вересень",
    "Жовтень",
    "Листопад",
    "Грудень",
  ],
  monthShort: ["Січ", "Лют", "Бер", "Кві", "Тра", "Чер", "Лип", "Сер", "Вер", "Жов", "Лис", "Гру"],
  dayFull: ["Неділя", "Понеділок", "Вівторок", "Середа", "Четвер", "П'ятниця", "Субота"],
  dayShort: ["Нд", "Пн", "Вт", "Ср", "Чт", "Пт", "Сб"],
  hours: "Години",
  minutes: "Хвилини",
  done: "Готово",
  clear: "Очистити",
  today: "Сьогодні",
  weekStart: 1,
  clockFormat: 24,
};

const core = {
  ok: "OK",
  cancel: "Скасувати",
  select: "Вибрати",
  "No data": "Немає даних",
  "Rows per page": "Рядків на сторінці",
  "Total pages": "Усього сторінок",
};

const formats = {
  timeFormat: "%H:%i",
  dateFormat: "%d.%m.%Y",
  monthYearFormat: "%F %Y",
  yearFormat: "%Y",
};

export default { core, calendar, formats, lang: "uk-UA" };
