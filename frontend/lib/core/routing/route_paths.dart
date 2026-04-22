/// Central definition of absolute route paths used by the app router.
abstract class RoutePath {
  RoutePath._();

  static const landingRoot = '/';
  static const boot = '/boot';
  static const landing = '/landing';
  static const login = '/login';
  static const signup = '/signup';
  static const verifyEmail = '/verify';
  static const forgotPassword = '/forgot-password';
  static const resetPassword = '/reset-password';
  static const home = '/home';
  static const courseIntro = '/course-intro';
  static const courseCatalog = '/courses';
  static const courseIntroRedirect = '/course-intro-redirect';
  static const messages = '/messages';
  static const directMessage = '/messages/:uid';
  static const profile = '/profile';
  static const createProfile = '/create-profile';
  static const welcome = '/welcome';
  static const profileSubscription = '/profile/subscription';
  static const checkout = '/checkout/web';
  static const checkoutMembership = '/checkout/membership';
  static const checkoutReturn = '/checkout/return';
  static const checkoutHostedCancel = '/checkout/cancel';
  static const profileView = '/profile/view/:id';
  static const teacherProfile = '/teacher/profile/:id';
  static const serviceDetail = '/service/:id';
  static const tarot = '/tarot';
  static const admin = '/admin';
  static const adminMedia = '/admin/media-control';
  static const adminSettings = '/admin/settings';
  static const studio = '/studio';
  static const teacherHome = '/teacher';
  static const teacherEditor = '/teacher/editor';
  static const studioProfile = '/studio/profile';
  static const subscribe = '/subscribe';
  static const booking = '/booking';
  static const privacy = '/privacy';
  static const terms = '/terms';
  static const checkoutSuccess = '/success';
  static const checkoutCancel = '/cancel';
  static const settings = '/settings';
  static const community = '/community';
  static const course = '/course/:slug';
  static const lesson = '/lesson/:id';

  static String courseWithSlug(String slug) => '/course/$slug';
  static String lessonWithId(String id) => '/lesson/$id';
  static String profileViewWithId(String id) => '/profile/view/$id';
  static String teacherProfileWithId(String id) => '/teacher/profile/$id';
  static String serviceDetailWithId(String id) => '/service/$id';
  static String directMessageWithUid(String uid) => '/messages/$uid';
}
