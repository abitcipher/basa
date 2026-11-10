export type Packets = {
  AvailabilityCalendar: {
    from: { "slot.picked": { startsAt: string } };
    to: { "availability.changed": { lotId: string } };
  };
  LessorCalendar: {
    from: { "booking.opened": { bookingId: string } };
    to: { "bookings.changed": {} };
  };
  ResourceTimeline: {
    from: { "booking.opened": { bookingId: string } };
    to: { "bookings.changed": {} };
  };
  BookingBoard: {
    from: { "booking.moved": { bookingId: string; to: string }; "booking.opened": { bookingId: string } };
    to: { "bookings.changed": {} };
  };
  LessorStats: {
    from: {};
    to: { "bookings.changed": {} };
  };
  AdminGrid: {
    from: {};
    to: {};
  };
  PhotoLibrary: {
    from: { "photos.deleted": { photos: { owner: "item" | "room"; id: string; key: string }[] } };
    to: { "photos.changed": {} };
  };
  PhotoGallery: {
    from: {};
    to: {};
  };
};
